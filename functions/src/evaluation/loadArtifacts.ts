/**
 * Load the latest stored LLM artifact for a prompt kind, plus reconstructed
 * grounding context. Context is current Firestore, not a frozen snapshot.
 */

import { DocumentData, getFirestore } from 'firebase-admin/firestore';
import { buildChatContext } from '../aiChat';
import { sportsLabel, wordingSport } from '../athleteSports';
import { loadCheckIns } from '../checkInLoader';
import { retrieveResearchChunks } from '../knowledgeAgent';
import { parsePrivacySettings } from '../privacySettings';
import { phrasePerformance, RiskAssessment } from '../riskModel';
import { PromptKind } from './rubric';

export interface EvalArtifact {
  kind: PromptKind;
  sourcePath: string;
  sourceId: string;
  outputText: string;
  contextText: string;
  generatorSource: string;
  skipReason?: string;
}

function assessmentFromLatest(data: DocumentData | undefined): RiskAssessment | null {
  if (!data || data.insufficientData || !data.riskLevel) return null;
  const band = (data.performancePrediction ?? 'AVERAGE') as RiskAssessment['performancePrediction'];
  const framed = phrasePerformance(undefined, band);
  return {
    riskLevel: data.riskLevel as RiskAssessment['riskLevel'],
    confidence: data.confidence ?? '',
    reason: data.reason ?? '',
    acwr: Number(data.acwr ?? 0),
    trainingLoad7d: Number(data.trainingLoad7d ?? 0),
    trainingLoad28dAvg: Number(data.trainingLoad28dAvg ?? 0),
    recoveryTrend: (data.recoveryTrend ?? 'stable') as RiskAssessment['recoveryTrend'],
    performancePrediction: band,
    performanceFrame: data.performanceFrame ?? framed.label,
    performanceFrameAxis: data.performanceFrameAxis ?? framed.axis,
  };
}

function latestSnapshot(data: DocumentData | undefined): string {
  if (!data) return 'No riskResults/latest document.';
  return [
    `LOCKED riskLevel: ${data.riskLevel ?? 'n/a'}`,
    `LOCKED performancePrediction: ${data.performancePrediction ?? 'n/a'} (${data.performanceFrame ?? ''})`,
    `ACWR: ${data.acwr ?? 'n/a'}`,
    `7-day load: ${data.trainingLoad7d ?? 'n/a'}`,
    `28-day avg weekly load: ${data.trainingLoad28dAvg ?? 'n/a'}`,
    `Recovery trend: ${data.recoveryTrend ?? 'n/a'}`,
    `Rule-based reason: ${data.reason ?? 'n/a'}`,
    `Primary recommendation: ${data.recommendation ?? 'n/a'}`,
    `Recommendation status: ${data.recommendationStatus ?? 'n/a'}`,
  ].join('\n');
}

async function loadAskAthleteIQ(athleteUid: string): Promise<EvalArtifact> {
  const db = getFirestore();
  const athleteRef = db.collection('athletes').doc(athleteUid);
  const snap = await athleteRef.collection('aiChat').orderBy('timestamp', 'desc').limit(30).get();
  const docs = snap.docs;
  const aiIdx = docs.findIndex((d) => d.data().isAi === true);
  if (aiIdx === -1) {
    return {
      kind: 'askAthleteIQ',
      sourcePath: `athletes/${athleteUid}/aiChat`,
      sourceId: '',
      outputText: '',
      contextText: '',
      generatorSource: 'missing',
      skipReason: 'No Ask AthleteIQ reply stored.',
    };
  }
  const ai = docs[aiIdx];
  const data = ai.data();
  const source = String(data.source ?? 'unknown');
  if (source === 'guard' || source === 'fallback') {
    return {
      kind: 'askAthleteIQ',
      sourcePath: ai.ref.path,
      sourceId: ai.id,
      outputText: String(data.text ?? ''),
      contextText: '',
      generatorSource: source,
      skipReason: `Stored reply source is ${source}, not llm.`,
    };
  }
  const questionDoc = docs.slice(aiIdx + 1).find((d) => d.data().isAi !== true);
  const question = String(questionDoc?.data()?.text ?? '(question not found)');
  const athleteSnap = await athleteRef.get();
  const athleteData = athleteSnap.data() ?? {};
  const entries = await loadCheckIns(athleteUid, 14);
  const riskSnap = await athleteRef.collection('riskResults').doc('latest').get();
  const riskData = riskSnap.data();
  const context = [
    `Athlete question: ${question}`,
    '',
    buildChatContext(
      entries,
      assessmentFromLatest(riskData),
      sportsLabel(athleteData) || wordingSport(athleteData, entries[0]).sport,
      String(athleteData.name ?? 'Athlete'),
      {
        recommendation: riskData?.recommendation ?? null,
        recommendationStatus: riskData?.recommendationStatus ?? null,
        privacy: parsePrivacySettings(athleteData.privacySettings),
        forCoach: false,
      },
    ),
  ].join('\n');
  return {
    kind: 'askAthleteIQ',
    sourcePath: ai.ref.path,
    sourceId: ai.id,
    outputText: String(data.text ?? ''),
    contextText: context,
    generatorSource: source === 'unknown' ? 'llm' : source,
  };
}

async function loadOrchestrator(athleteUid: string): Promise<EvalArtifact> {
  const db = getFirestore();
  const tracesSnap = await db
    .collection('athletes')
    .doc(athleteUid)
    .collection('orchestratorTraces')
    .limit(20)
    .get();
  const traces = [...tracesSnap.docs].sort((a, b) => {
    const ta = String(a.data().decidedAt ?? a.data().timestamp ?? '');
    const tb = String(b.data().decidedAt ?? b.data().timestamp ?? '');
    return tb.localeCompare(ta);
  });
  const doc = traces[0];
  const latestSnap = await db
    .collection('athletes')
    .doc(athleteUid)
    .collection('riskResults')
    .doc('latest')
    .get();
  const latest = latestSnap.data();
  if (!doc) {
    if (latest?.recommendation) {
      const source = String(latest.orchestratorSource ?? 'unknown');
      return wrapOrSkip(
        'orchestrator',
        latestSnap.ref.path,
        'latest',
        JSON.stringify(
          {
            action: latest.recommendation,
            orchestratorNote: latest.reason ?? '',
            safetyOverride: latest.orchestratorSafetyOverride ?? false,
          },
          null,
          2,
        ),
        latestSnapshot(latest),
        source,
        source === 'agent' || source === 'unknown' ? undefined : `Source is ${source}, not agent.`,
      );
    }
    return {
      kind: 'orchestrator',
      sourcePath: `athletes/${athleteUid}/orchestratorTraces`,
      sourceId: '',
      outputText: '',
      contextText: '',
      generatorSource: 'missing',
      skipReason: 'No orchestrator trace or latest recommendation stored.',
    };
  }
  const data = doc.data();
  const source = String(data.source ?? 'unknown');
  const output = JSON.stringify(
    {
      action: data.action,
      orchestratorNote: data.orchestratorNote,
      safetyOverride: data.safetyOverride,
      why: Array.isArray(data.trace)
        ? data.trace.find((s: { type?: string }) => s?.type === 'decision')?.why
        : undefined,
    },
    null,
    2,
  );
  const toolBits = Array.isArray(data.trace)
    ? data.trace
        .filter((s: { type?: string }) => s?.type === 'tool')
        .map(
          (s: { tool?: string; output?: string }) =>
            `Tool ${s.tool}: ${String(s.output ?? '').slice(0, 800)}`,
        )
        .join('\n')
    : '';
  return wrapOrSkip(
    'orchestrator',
    doc.ref.path,
    doc.id,
    output,
    [latestSnapshot(latest), toolBits].filter(Boolean).join('\n\n'),
    source,
    source === 'agent' || source === 'unknown'
      ? undefined
      : `Source is ${source}, not the agent path.`,
  );
}

async function loadGraded(athleteUid: string): Promise<EvalArtifact> {
  const latest = await loadLatest(athleteUid);
  const source = String(latest.data?.gradedOptionsSource ?? 'unknown');
  const options = latest.data?.gradedOptions;
  if (!Array.isArray(options) || options.length === 0) {
    return {
      kind: 'graded',
      sourcePath: latest.path,
      sourceId: 'latest',
      outputText: '',
      contextText: '',
      generatorSource: source,
      skipReason: 'No gradedOptions stored.',
    };
  }
  return wrapOrSkip(
    'graded',
    latest.path,
    'latest',
    JSON.stringify(options, null, 2),
    latestSnapshot(latest.data),
    source,
    source === 'llm' || source === 'unknown' ? undefined : `Source is ${source}, not llm.`,
  );
}

async function loadExplain(athleteUid: string): Promise<EvalArtifact> {
  const latest = await loadLatest(athleteUid);
  const source = String(latest.data?.explanationSource ?? 'unknown');
  const output = JSON.stringify(
    {
      riskLevelReasoningLLM: latest.data?.riskLevelReasoningLLM ?? '',
      riskLevelPatternFlag: latest.data?.riskLevelPatternFlag ?? null,
      performanceReasoningLLM: latest.data?.performanceReasoningLLM ?? '',
    },
    null,
    2,
  );
  if (!latest.data?.riskLevelReasoningLLM && !latest.data?.performanceReasoningLLM) {
    return {
      kind: 'explain',
      sourcePath: latest.path,
      sourceId: 'latest',
      outputText: '',
      contextText: '',
      generatorSource: source,
      skipReason: 'No hybrid explanation fields stored.',
    };
  }
  const entries = await loadCheckIns(athleteUid, 5);
  const last5 = entries
    .slice(0, 5)
    .map((e) => {
      const parts = [`${e.date}: fatigue ${e.fatigueScore}/5`, `load ${e.trainingLoad ?? 0}`];
      if (e.sleepHours != null) parts.push(`sleep ${e.sleepHours.toFixed(1)}h`);
      if (e.hrv != null) parts.push(`HRV ${e.hrv}`);
      return `  ${parts.join(', ')}`;
    })
    .join('\n');
  return wrapOrSkip(
    'explain',
    latest.path,
    'latest',
    output,
    `${latestSnapshot(latest.data)}\nLast 5 check-ins:\n${last5 || 'none'}`,
    source,
    source === 'llm' || source === 'unknown' ? undefined : `Source is ${source}, not llm.`,
  );
}

async function loadResearch(athleteUid: string): Promise<EvalArtifact> {
  const latest = await loadLatest(athleteUid);
  const source = String(latest.data?.researchSource ?? 'unknown');
  const note = String(latest.data?.researchNote ?? '');
  if (!note) {
    return {
      kind: 'research',
      sourcePath: latest.path,
      sourceId: 'latest',
      outputText: '',
      contextText: '',
      generatorSource: source,
      skipReason: 'No researchNote stored.',
    };
  }
  const output = JSON.stringify(
    {
      note,
      citations: latest.data?.researchCitations ?? [],
    },
    null,
    2,
  );
  const assessment = assessmentFromLatest(latest.data);
  let retrieved = '';
  if (assessment) {
    try {
      const chunks = await retrieveResearchChunks(assessment, 3);
      retrieved = chunks
        .map((d, i) => `[${i + 1}] tag: ${d.metadata.tag}\nsource: ${d.metadata.source}\n${d.pageContent}`)
        .join('\n\n');
    } catch {
      retrieved = '(could not re-retrieve corpus chunks)';
    }
  }
  return wrapOrSkip(
    'research',
    latest.path,
    'latest',
    output,
    `${latestSnapshot(latest.data)}\n\nRetrieved notes (re-fetched, may differ from original):\n${retrieved}`,
    source,
    source === 'llm' || source === 'unknown' ? undefined : `Source is ${source}, not llm.`,
  );
}

async function loadTriage(athleteUid: string): Promise<EvalArtifact> {
  const db = getFirestore();
  const snap = await db
    .collection('athletes')
    .doc(athleteUid)
    .collection('painReports')
    .orderBy('date', 'desc')
    .limit(10)
    .get();
  const doc = snap.docs[0];
  if (!doc) {
    return {
      kind: 'triage',
      sourcePath: `athletes/${athleteUid}/painReports`,
      sourceId: '',
      outputText: '',
      contextText: '',
      generatorSource: 'missing',
      skipReason: 'No pain reports stored.',
    };
  }
  const data = doc.data();
  const source = String(data.urgencySource ?? 'unknown');
  return wrapOrSkip(
    'triage',
    doc.ref.path,
    doc.id,
    JSON.stringify(
      { urgency: data.urgency, reason: data.urgencyReason },
      null,
      2,
    ),
    `Body areas: ${JSON.stringify(data.areas ?? [])}\nAthlete notes: ${data.note ?? '(none)'}`,
    source,
    source === 'llm' || source === 'unknown' ? undefined : `Source is ${source}, not llm.`,
  );
}

async function loadClassify(athleteUid: string): Promise<EvalArtifact> {
  const db = getFirestore();
  const snap = await db.collection('athletes').doc(athleteUid).get();
  const data = snap.data() ?? {};
  const source = String(data.sportClassificationSource ?? 'unknown');
  const sport = String(data.sport ?? '');
  if (!sport) {
    return {
      kind: 'classify',
      sourcePath: snap.ref.path,
      sourceId: athleteUid,
      outputText: '',
      contextText: '',
      generatorSource: source,
      skipReason: 'No sport stored on the athlete profile.',
    };
  }
  return wrapOrSkip(
    'classify',
    snap.ref.path,
    athleteUid,
    JSON.stringify(
      {
        sport,
        sportGroup: data.sportGroup,
        confidence: data.sportClassificationConfidence,
      },
      null,
      2,
    ),
    `Sport name entered by athlete: "${sport}"`,
    source,
    source === 'llm' || source === 'unknown' ? undefined : `Source is ${source}, not llm.`,
  );
}

async function loadWeekly(athleteUid: string): Promise<EvalArtifact> {
  const db = getFirestore();
  const snap = await db
    .collection('athletes')
    .doc(athleteUid)
    .collection('weeklyReports')
    .orderBy('weekStart', 'desc')
    .limit(5)
    .get();
  const doc = snap.docs[0];
  if (!doc) {
    return {
      kind: 'weekly',
      sourcePath: `athletes/${athleteUid}/weeklyReports`,
      sourceId: '',
      outputText: '',
      contextText: '',
      generatorSource: 'missing',
      skipReason: 'No weekly report stored.',
    };
  }
  const data = doc.data();
  const source = String(data.narrativeSource ?? 'unknown');
  const stats = { ...data };
  delete stats.narrative;
  return wrapOrSkip(
    'weekly',
    doc.ref.path,
    doc.id,
    String(data.narrative ?? ''),
    JSON.stringify(stats, null, 2),
    source,
    source === 'llm' || source === 'unknown' ? undefined : `Source is ${source}, not llm.`,
  );
}

async function loadLatest(
  athleteUid: string,
): Promise<{ path: string; data: DocumentData | undefined }> {
  const ref = getFirestore()
    .collection('athletes')
    .doc(athleteUid)
    .collection('riskResults')
    .doc('latest');
  const snap = await ref.get();
  return { path: ref.path, data: snap.data() };
}

function wrapOrSkip(
  kind: PromptKind,
  sourcePath: string,
  sourceId: string,
  outputText: string,
  contextText: string,
  generatorSource: string,
  skipReason?: string,
): EvalArtifact {
  return {
    kind,
    sourcePath,
    sourceId,
    outputText,
    contextText,
    generatorSource,
    skipReason,
  };
}

export async function loadArtifact(
  athleteUid: string,
  kind: PromptKind,
): Promise<EvalArtifact> {
  switch (kind) {
    case 'askAthleteIQ':
      return loadAskAthleteIQ(athleteUid);
    case 'orchestrator':
      return loadOrchestrator(athleteUid);
    case 'graded':
      return loadGraded(athleteUid);
    case 'explain':
      return loadExplain(athleteUid);
    case 'research':
      return loadResearch(athleteUid);
    case 'triage':
      return loadTriage(athleteUid);
    case 'classify':
      return loadClassify(athleteUid);
    case 'weekly':
      return loadWeekly(athleteUid);
    default: {
      const never: never = kind;
      throw new Error(`Unknown kind: ${never}`);
    }
  }
}
