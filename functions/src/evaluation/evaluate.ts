/**
 * Manual LLM-as-judge run: load a stored artifact, score it, persist the
 * result under athletes/{uid}/llmEvaluations/{id}.
 */

import { getFirestore } from 'firebase-admin/firestore';
import { judgeOutput, JudgeResult, LLM_JUDGE_LIMITATIONS } from './judge';
import { loadArtifact } from './loadArtifacts';
import { FIRST_PASS_KINDS, isPromptKind, PromptKind } from './rubric';

export interface HumanReview {
  reviewedAt: string;
  reviewerUid: string;
  agreement: 'agree' | 'disagree';
  disagreedItemIds: string[];
  note: string;
}

export interface EvaluationRecord extends JudgeResult {
  athleteUid: string;
  sourcePath: string;
  sourceId: string;
  generatorSource: string;
  outputPreview: string;
  contextPreview: string;
  judgedAt: string;
  judgeModel: string;
  limitations: string;
  humanReview: HumanReview | null;
}

export interface EvaluateOneResult {
  evalId: string | null;
  skipped: boolean;
  skipReason?: string;
  kind: PromptKind;
  record?: EvaluationRecord;
}

function toRecord(
  athleteUid: string,
  judged: JudgeResult,
  sourcePath: string,
  sourceId: string,
  generatorSource: string,
  outputText: string,
  contextText: string,
): EvaluationRecord {
  return {
    ...judged,
    athleteUid,
    sourcePath,
    sourceId,
    generatorSource,
    outputPreview: outputText.slice(0, 1500),
    contextPreview: contextText.slice(0, 2000),
    judgedAt: new Date().toISOString(),
    judgeModel: process.env.ANTHROPIC_MODEL ?? 'claude-sonnet-5',
    limitations: LLM_JUDGE_LIMITATIONS,
    humanReview: null,
  };
}

export async function evaluateStoredOutput(opts: {
  athleteUid: string;
  kind: PromptKind;
}): Promise<EvaluateOneResult> {
  const artifact = await loadArtifact(opts.athleteUid, opts.kind);
  if (artifact.skipReason) {
    return {
      evalId: null,
      skipped: true,
      skipReason: artifact.skipReason,
      kind: opts.kind,
    };
  }

  const judged = await judgeOutput({
    kind: opts.kind,
    outputText: artifact.outputText,
    contextText: artifact.contextText,
  });
  const record = toRecord(
    opts.athleteUid,
    judged,
    artifact.sourcePath,
    artifact.sourceId,
    artifact.generatorSource,
    artifact.outputText,
    artifact.contextText,
  );

  const db = getFirestore();
  const ref = await db
    .collection('athletes')
    .doc(opts.athleteUid)
    .collection('llmEvaluations')
    .add(record);

  return { evalId: ref.id, skipped: false, kind: opts.kind, record };
}

export async function evaluateAthleteHistory(opts: {
  athleteUid: string;
  kinds?: PromptKind[];
}): Promise<{ results: EvaluateOneResult[] }> {
  const kinds = opts.kinds?.length ? opts.kinds : FIRST_PASS_KINDS;
  const results: EvaluateOneResult[] = [];
  for (const kind of kinds) {
    results.push(await evaluateStoredOutput({ athleteUid: opts.athleteUid, kind }));
  }
  return { results };
}

export async function applyHumanReview(opts: {
  athleteUid: string;
  evalId: string;
  reviewerUid: string;
  agreement: 'agree' | 'disagree';
  disagreedItemIds?: string[];
  note?: string;
}): Promise<HumanReview> {
  const db = getFirestore();
  const ref = db
    .collection('athletes')
    .doc(opts.athleteUid)
    .collection('llmEvaluations')
    .doc(opts.evalId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new Error('Evaluation not found.');
  }
  const review: HumanReview = {
    reviewedAt: new Date().toISOString(),
    reviewerUid: opts.reviewerUid,
    agreement: opts.agreement,
    disagreedItemIds: opts.disagreedItemIds ?? [],
    note: (opts.note ?? '').trim(),
  };
  await ref.update({ humanReview: review });
  return review;
}

export function parseKinds(raw: unknown): PromptKind[] | undefined {
  if (raw == null) return undefined;
  if (!Array.isArray(raw)) return undefined;
  const kinds = raw.filter(isPromptKind);
  return kinds.length > 0 ? kinds : undefined;
}
