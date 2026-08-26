import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import {
  averagePresent,
  calendarWindow,
  isFatiguePersistent,
  utcDateKey,
} from './calculations';
import { loadCheckIns } from './checkInLoader';
import { enrichAssessmentExplanation } from './explainabilityLlm';
import { generateGradedOptions } from './gradedRecommendations';
import { generateResearchNote } from './knowledgeAgent';
import { runOrchestratorAgent } from './orchestratorAgent';
import { assessRisk } from './riskModel';
import { wordingSport } from './athleteSports';
import { loadTeamSettings } from './teamSettings';
import { writeAthleteRiskView } from './privacyViews';

/** Section 6 / 11 / 17.1 — every new assessment waits for coach review. */
export const PENDING_RECOMMENDATION_STATUS = 'pending';

/** Pipeline writes never skip the Human Approval Step. */
export function statusForNewRiskWrite(): typeof PENDING_RECOMMENDATION_STATUS {
  return PENDING_RECOMMENDATION_STATUS;
}

export type RiskPipelineResult =
  | { status: 'not_found' }
  | { status: 'insufficient_data'; checkInCount: number }
  | { status: 'ok'; riskLevel: string };

/**
 * Shared Risk → Performance → Orchestrator pipeline.
 * Used by the on-demand callable and the nightly scheduled job.
 *
 * recommendationStatus is always `pending` on write — including Orchestrator
 * (E3) and graded-options (E4) output. Coach review is the only path to
 * approved | modified | rejected.
 */
export async function runRiskPipeline(
  athleteUid: string,
): Promise<RiskPipelineResult> {
  const db = getFirestore();
  const athleteRef = db.collection('athletes').doc(athleteUid);
  const athleteDoc = await athleteRef.get();
  if (!athleteDoc.exists) {
    return { status: 'not_found' };
  }
  const athleteData = athleteDoc.data()!;

  const entries = await loadCheckIns(athleteUid, 35);
  const resultsCol = athleteRef.collection('riskResults');
  const resultRef = resultsCol.doc('latest');

  if (entries.length < 5) {
    const insufficient = {
      insufficientData: true,
      checkInCount: entries.length,
    };
    await resultRef.set(insufficient, { merge: true });
    await writeAthleteRiskView(athleteUid, insufficient);
    return { status: 'insufficient_data', checkInCount: entries.length };
  }

  const latestSession = entries[0];
  const { sport, sportGroup } = wordingSport(athleteData, latestSession);
  const coachUid =
    typeof athleteData.coachUid === 'string' ? athleteData.coachUid : null;
  const teamSettings = await loadTeamSettings(coachUid);
  const asOf = utcDateKey();
  const assessment = assessRisk(entries, sportGroup, asOf);

  // Classification is already locked. LLM may only add prose fields.
  let riskLevelReasoningLLM = assessment.reason;
  let riskLevelPatternFlag: string | null = null;
  let performanceReasoningLLM = '';
  let explanationSource = 'rules';
  try {
    const explained = await enrichAssessmentExplanation(assessment, entries);
    riskLevelReasoningLLM = explained.riskLevelReasoningLLM;
    riskLevelPatternFlag = explained.riskLevelPatternFlag;
    performanceReasoningLLM = explained.performanceReasoningLLM;
    explanationSource = explained.source;
  } catch (err) {
    logger.warn('explainability LLM skipped', err);
  }

  const orchestrator = await runOrchestratorAgent({
    athleteUid,
    sportGroup,
    defaultActionPercent: teamSettings.defaultActionPercent,
    persistTrace: true,
    asOf,
  });

  const recommendationStatus = statusForNewRiskWrite();

  let researchNote = '';
  let researchCitations: { tag: string; text: string; source: string }[] = [];
  let researchSource = 'retrieved';
  try {
    const research = await generateResearchNote(assessment);
    researchNote = research.note;
    researchCitations = research.citations;
    researchSource = research.source;
  } catch (err) {
    logger.warn('knowledge agent skipped', err);
  }

  let gradedOptions: { tier: string; action: string; reason: string }[] = [];
  let gradedOptionsSource = 'rules';
  try {
    const graded = await generateGradedOptions({
      assessment,
      sportGroup,
      sport,
      primaryAction: orchestrator.action,
      primaryNote: orchestrator.orchestratorNote,
      defaultActionPercent: teamSettings.defaultActionPercent,
    });
    gradedOptions = graded.options;
    gradedOptionsSource = graded.source;
  } catch (err) {
    logger.warn('graded options skipped', err);
  }

  const avgFatigue7d = averagePresent(
    calendarWindow(entries, 7, asOf).map((d) => d.entry?.fatigueScore),
  );
  const fatiguePersistent = isFatiguePersistent(entries, asOf);
  const calculatedAt = new Date().toISOString();
  const dayKey = asOf;

  const payload = {
    riskLevel: assessment.riskLevel,
    confidence: assessment.confidence,
    reason: `${assessment.reason} ${orchestrator.orchestratorNote}`,
    riskLevelReasoningLLM,
    riskLevelPatternFlag,
    performanceReasoningLLM,
    explanationSource,
    acwr: assessment.acwr,
    trainingLoad7d: assessment.trainingLoad7d,
    trainingLoad28dAvg: assessment.trainingLoad28dAvg,
    recoveryTrend: assessment.recoveryTrend,
    performancePrediction: assessment.performancePrediction,
    performanceFrame: assessment.performanceFrame,
    performanceFrameAxis: assessment.performanceFrameAxis,
    recommendation: orchestrator.action,
    recommendationStatus,
    orchestratorSource: orchestrator.source,
    orchestratorSafetyOverride: orchestrator.safetyOverride,
    ruleBasedRecommendation: orchestrator.ruleBased.action,
    ruleBasedOrchestratorNote: orchestrator.ruleBased.orchestratorNote,
    orchestratorAgreedWithRules: orchestrator.agreedWithRules,
    orchestratorConflict: {
      ...orchestrator.ruleBased.conflict,
      actionWon: orchestrator.action,
      ruleBasedAction: orchestrator.ruleBased.action,
      safetyOverride: orchestrator.safetyOverride,
      agreedWithRules: orchestrator.agreedWithRules,
      source: orchestrator.source,
    },
    researchNote,
    researchCitations,
    researchSource,
    gradedOptions,
    gradedOptionsSource,
    avgFatigue7d,
    fatiguePersistent,
    insufficientData: false,
    calculatedAt,
  };

  await resultRef.set(payload);
  await writeAthleteRiskView(athleteUid, payload);

  // Dated snapshot for forecast / ACWR charts. Recommendation review
  // still lives only on `latest`.
  await resultsCol.doc(dayKey).set({
    kind: 'snapshot',
    riskLevel: assessment.riskLevel,
    acwr: assessment.acwr,
    trainingLoad7d: assessment.trainingLoad7d,
    trainingLoad28dAvg: assessment.trainingLoad28dAvg,
    recoveryTrend: assessment.recoveryTrend,
    performancePrediction: assessment.performancePrediction,
    performanceFrame: assessment.performanceFrame,
    performanceFrameAxis: assessment.performanceFrameAxis,
    avgFatigue7d,
    fatiguePersistent,
    insufficientData: false,
    calculatedAt,
  });

  return { status: 'ok', riskLevel: assessment.riskLevel };
}
