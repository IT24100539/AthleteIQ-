/**
 * Real output guardrails for LLM JSON. Prompts still *ask* for JSON;
 * this module is the actual boundary: Zod shape + business rules.
 * Failures must fall back to the deterministic path — never patch and ship.
 */

import { z } from 'zod';
import { logger } from 'firebase-functions';
import { RiskLevel } from './riskModel';
import { SportGroup } from './recommendationEngine';

export type GuardrailResult<T> =
  | { ok: true; data: T }
  | { ok: false; reason: string };

export function extractJsonObject(raw: string): unknown | null {
  const trimmed = raw.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  const start = trimmed.indexOf('{');
  const end = trimmed.lastIndexOf('}');
  if (start === -1 || end <= start) return null;
  try {
    return JSON.parse(trimmed.slice(start, end + 1));
  } catch {
    return null;
  }
}

export function parseLlmJson<T>(raw: string, schema: z.ZodTypeAny): GuardrailResult<T> {
  const obj = extractJsonObject(raw);
  if (obj == null) {
    return { ok: false, reason: 'malformed_json' };
  }
  const parsed = schema.safeParse(obj);
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    const path = issue?.path?.length ? issue.path.join('.') : 'root';
    return { ok: false, reason: `schema:${path}:${issue?.code ?? 'invalid'}` };
  }
  return { ok: true, data: parsed.data as T };
}

export function logGuardrailFallback(kind: string, reason: string): void {
  logger.warn('llm guardrail: discarded output, using rule-based fallback', { kind, reason });
}

/** Full unrestricted training — blocked when risk is MEDIUM or HIGH. */
export function looksLikeFullTraining(action: string): boolean {
  const a = action.toLowerCase();
  return (
    a.includes('continue training as planned') ||
    a.includes('train as planned') ||
    a.includes('train as hard as planned') ||
    a.includes('full intensity') ||
    a.includes('full unrestricted') ||
    a.includes('no change')
  );
}

export function elevatedRiskForbidsFullTraining(
  riskLevel: RiskLevel | string,
  actions: string[],
): boolean {
  if (riskLevel !== 'HIGH' && riskLevel !== 'MEDIUM') return false;
  return actions.some((a) => looksLikeFullTraining(a));
}

export function actionInAllowedList(action: string, allowed: string[]): boolean {
  return allowed.includes(action);
}

/**
 * True if prose tries to replace the locked risk band (upgrade / downgrade /
 * "should be HIGH" when locked is MEDIUM, etc.). Mentioning the locked label
 * itself is expected.
 */
export function contradictsLockedRiskLevel(prose: string, locked: RiskLevel): boolean {
  const others = (['LOW', 'MEDIUM', 'HIGH'] as const).filter((l) => l !== locked);
  const joined = others.join('|');
  const re = new RegExp(
    String.raw`\b(?:risk\s*(?:level)?\s*(?:is|as|=|:|to)\s*|classified as\s*|upgrade(?:d)?(?:\s+the\s+risk)?\s+to\s*|downgrade(?:d)?(?:\s+the\s+risk)?\s+to\s*|should be\s+|actually\s+|reclassif\w*\s+(?:as|to)\s+)(${joined})\b`,
    'i',
  );
  return re.test(prose);
}

const nonEmpty = z.string().trim().min(1);

export const orchestratorOutputSchema = z
  .object({
    action: nonEmpty,
    orchestratorNote: nonEmpty,
    why: z.string().trim().optional(),
  })
  .strict();

export type OrchestratorLlmOutput = z.infer<typeof orchestratorOutputSchema>;

export function parseOrchestratorOutput(
  raw: string,
  opts: { allowedActions: string[]; riskLevel: RiskLevel },
): GuardrailResult<OrchestratorLlmOutput> {
  const shape = parseLlmJson<OrchestratorLlmOutput>(raw, orchestratorOutputSchema);
  if (!shape.ok) return shape;
  const action = shape.data.action.trim();
  if (!actionInAllowedList(action, opts.allowedActions)) {
    return { ok: false, reason: 'business:action_not_in_allowed_list' };
  }
  if (elevatedRiskForbidsFullTraining(opts.riskLevel, [action])) {
    return { ok: false, reason: 'business:full_training_when_elevated_risk' };
  }
  return { ok: true, data: { ...shape.data, action } };
}

const gradedTierSchema = z.enum(['Conservative', 'Moderate', 'Minimal change']);

export const gradedOutputSchema = z
  .object({
    options: z
      .array(
        z
          .object({
            tier: gradedTierSchema,
            action: nonEmpty,
            reason: nonEmpty,
          })
          .strict(),
      )
      .length(3),
  })
  .strict()
  .refine(
    (v) => new Set(v.options.map((o) => o.tier)).size === 3,
    { message: 'tiers_must_be_unique' },
  );

export type GradedLlmOutput = z.infer<typeof gradedOutputSchema>;

export function parseGradedOutput(
  raw: string,
  opts: { riskLevel: RiskLevel },
): GuardrailResult<GradedLlmOutput> {
  const shape = parseLlmJson<GradedLlmOutput>(raw, gradedOutputSchema);
  if (!shape.ok) return shape;
  const actions = shape.data.options.map((o) => o.action);
  if (elevatedRiskForbidsFullTraining(opts.riskLevel, actions)) {
    return { ok: false, reason: 'business:full_training_when_elevated_risk' };
  }
  return shape;
}

export const explainOutputSchema = z
  .object({
    riskLevelReasoningLLM: nonEmpty,
    riskLevelPatternFlag: z.preprocess((v) => {
      if (v == null) return null;
      if (typeof v !== 'string') return v;
      const t = v.trim();
      return !t || t.toLowerCase() === 'null' ? null : t;
    }, z.string().nullable()),
    performanceReasoningLLM: nonEmpty,
  })
  .strict();

export type ExplainLlmOutput = {
  riskLevelReasoningLLM: string;
  riskLevelPatternFlag: string | null;
  performanceReasoningLLM: string;
};

export function parseExplainOutput(
  raw: string,
  opts: { lockedRiskLevel: RiskLevel },
): GuardrailResult<ExplainLlmOutput> {
  const obj = extractJsonObject(raw);
  if (obj && typeof obj === 'object' && !Array.isArray(obj)) {
    const rec = obj as Record<string, unknown>;
    if ('riskLevel' in rec && rec.riskLevel !== opts.lockedRiskLevel) {
      return { ok: false, reason: 'business:attempted_to_change_locked_riskLevel' };
    }
    if (
      'performancePrediction' in rec &&
      typeof rec.performancePrediction === 'string' &&
      rec.performancePrediction.length > 0
    ) {
      return { ok: false, reason: 'business:attempted_to_emit_performancePrediction' };
    }
  }
  const shape = parseLlmJson<ExplainLlmOutput>(raw, explainOutputSchema);
  if (!shape.ok) return shape;
  const combined = [
    shape.data.riskLevelReasoningLLM,
    shape.data.riskLevelPatternFlag ?? '',
    shape.data.performanceReasoningLLM,
  ].join(' ');
  if (contradictsLockedRiskLevel(combined, opts.lockedRiskLevel)) {
    return { ok: false, reason: 'business:prose_contradicts_locked_riskLevel' };
  }
  return shape;
}

export const researchOutputSchema = z
  .object({
    note: nonEmpty,
    citations: z
      .array(
        z
          .object({
            tag: nonEmpty,
            text: nonEmpty,
            source: nonEmpty,
          })
          .strict(),
      )
      .min(1)
      .max(3),
  })
  .strict();

export type ResearchLlmOutput = {
  note: string;
  citations: { tag: string; text: string; source: string }[];
};

export function parseResearchOutput(raw: string): GuardrailResult<ResearchLlmOutput> {
  return parseLlmJson<ResearchLlmOutput>(raw, researchOutputSchema);
}

export const triageOutputSchema = z
  .object({
    urgency: z.preprocess(
      (v) => (typeof v === 'string' ? v.trim().toUpperCase() : v),
      z.enum(['LOW', 'MEDIUM', 'HIGH']),
    ),
    reason: nonEmpty,
  })
  .strict();

export type TriageLlmOutput = {
  urgency: 'LOW' | 'MEDIUM' | 'HIGH';
  reason: string;
};

export function parseTriageOutput(raw: string): GuardrailResult<TriageLlmOutput> {
  return parseLlmJson<TriageLlmOutput>(raw, triageOutputSchema);
}

const sportGroups = [
  'endurance',
  'teamContact',
  'strengthPower',
  'skillPrecision',
  'combat',
  'other',
] as const satisfies readonly SportGroup[];

export const classifyOutputSchema = z
  .object({
    sportGroup: z.enum(sportGroups),
    confidence: z.preprocess(
      (v) => (typeof v === 'string' ? v.trim().toLowerCase() : v),
      z.enum(['high', 'low']),
    ),
    reason: z.string().trim().optional(),
  })
  .strict();

export type ClassifyLlmOutput = {
  sportGroup: SportGroup;
  confidence: 'high' | 'low';
  reason?: string;
};

export function parseClassifyOutput(raw: string): GuardrailResult<ClassifyLlmOutput> {
  return parseLlmJson<ClassifyLlmOutput>(raw, classifyOutputSchema);
}

export const weeklyOutputSchema = z
  .object({
    narrative: nonEmpty,
  })
  .strict();

export type WeeklyLlmOutput = { narrative: string };

export function parseWeeklyOutput(raw: string): GuardrailResult<WeeklyLlmOutput> {
  return parseLlmJson<WeeklyLlmOutput>(raw, weeklyOutputSchema);
}

export const judgeItemSchema = z
  .object({
    id: nonEmpty,
    pass: z.boolean(),
    evidence: z.string().default(''),
    reason: z.string().default(''),
  })
  .strict();

export const judgeOutputSchema = z
  .object({
    items: z.array(judgeItemSchema).min(1),
    overallScore: z.number().optional(),
    verbosityBiasRisk: z.enum(['low', 'medium', 'high']).optional(),
    summary: z.string().optional(),
  })
  .strict();

export type JudgeLlmOutput = {
  items: { id: string; pass: boolean; evidence: string; reason: string }[];
  overallScore?: number;
  verbosityBiasRisk?: 'low' | 'medium' | 'high';
  summary?: string;
};

export function parseJudgeShape(raw: string): GuardrailResult<JudgeLlmOutput> {
  return parseLlmJson<JudgeLlmOutput>(raw, judgeOutputSchema);
}
