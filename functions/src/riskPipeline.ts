import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { isFatiguePersistent } from './calculations';
import { loadCheckIns } from './checkInLoader';
import { enrichAssessmentExplanation } from './explainabilityLlm';
import { generateGradedOptions } from './gradedRecommendations';
import { generateResearchNote } from './knowledgeAgent';
import { runOrchestratorAgent } from './orchestratorAgent';
import { assessRisk } from './riskModel';
import { wordingSport } from './athleteSports';
import { loadTeamSettings } from './teamSettings';
import { writeAthleteRiskView } from './privacyViews';

export type RiskPipelineResult =
  | { status: 'not_found' }
  | { status: 'insufficient_data'; checkInCount: number }
  | { status: 'ok'; riskLevel: string };

export type RunRiskPipelineOptions = {
  /**
   * Callable / new check-in: always `pending` so the coach re-reviews.
   * Nightly: keep the existing status when the action text is unchanged.
   */
  resetRecommendationStatus?: boolean;
};

/**
 * Shared Risk → Performance → Orchestrator pipeline.
 * Used by the on-demand callable and the nightly scheduled job.
 */
export async function runRiskPipeline(
  athleteUid: string,
  options: RunRiskPipelineOptions = {},
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
  const assessment = assessRisk(entries, sportGroup);

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
  });

  const resetStatus = options.resetRecommendationStatus ?? true;
  const existing = resetStatus ? undefined : (await resultRef.get()).data();
  const recommendationStatus =
    !resetStatus &&
    existing?.recommendation === orchestrator.action &&
    typeof existing?.recommendationStatus === 'string'
      ? existing.recommendationStatus
      : 'pending';

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

  const last7 = entries.slice(0, 7);
  const avgFatigue7d =
    last7.length === 0
      ? null
      : last7.reduce((sum, e) => sum + (e.fatigueScore ?? 3), 0) / last7.length;
  const fatiguePersistent = isFatiguePersistent(entries);
  const calculatedAt = new Date().toISOString();
  const dayKey = /^\d{4}-\d{2}-\d{2}$/.test(entries[0]?.date)
    ? entries[0].date
    : calculatedAt.slice(0, 10);

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
