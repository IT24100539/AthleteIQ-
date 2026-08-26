/**
 * Section 16.3 — Graded recommendation options (Conservative / Moderate /
 * Minimal change). Generated via LangChain + Anthropic (Phase E2 stack).
 * Stored additively as `gradedOptions` alongside the primary
 * `recommendation` field.
 */

import { StringOutputParser } from '@langchain/core/output_parsers';
import { createChatAnthropic } from './anthropic';
import { ChatPromptTemplate } from '@langchain/core/prompts';
import { logger } from 'firebase-functions';
import {
  buildSportTemplates,
  LOW_DECLINING_ACTION,
  SportGroup,
} from './recommendationEngine';
import {
  GROUNDING_INSTRUCTION,
  jsonExampleForChatPrompt,
  MEDICAL_DISCLAIMER,
  RISK_OVERRIDES_PERFORMANCE_CLAUSE,
} from './promptFragments';
import { RiskAssessment } from './riskModel';
import { logGuardrailFallback, parseGradedOutput } from './llmGuardrails';

export type GradedOptionTier = 'Conservative' | 'Moderate' | 'Minimal change';

export interface GradedOption {
  tier: GradedOptionTier;
  action: string;
  reason: string;
}

export interface GradedOptionsResult {
  options: GradedOption[];
  source: 'llm' | 'rules';
}

export const GRADED_PROMPT = `You are AthleteIQ's recommendation writer (Section 16.3). Given an athlete's risk signals and sport, produce exactly 3 graded training options for a coach to choose from.

Tiers (always use these exact labels):
1. Conservative — maximum load reduction; safest choice when risk is elevated.
2. Moderate — balanced adjustment; partial reduction while keeping some structure.
3. Minimal change — smallest adjustment that still acknowledges the risk/performance signals.

Rules:
- Each option needs a one-line "reason" (max 20 words).
- Wording must fit the sport group provided.
- ${GROUNDING_INSTRUCTION}
- ${RISK_OVERRIDES_PERFORMANCE_CLAUSE}
- ${MEDICAL_DISCLAIMER}
- If risk is LOW, Minimal change may be "continue as planned".
- Return JSON only, no markdown:
${jsonExampleForChatPrompt('{"options":[{"tier":"Conservative","action":"...","reason":"..."},{"tier":"Moderate","action":"...","reason":"..."},{"tier":"Minimal change","action":"...","reason":"..."}]}')}`;

/** Rule-based fallback when the LLM is unavailable. */
export function fallbackGradedOptions(
  assessment: RiskAssessment,
  sportGroup: SportGroup,
  primaryAction: string,
  defaultActionPercent?: number,
): GradedOption[] {
  const t = buildSportTemplates(defaultActionPercent)[sportGroup] ?? buildSportTemplates(defaultActionPercent).other;
  const { riskLevel, performancePrediction } = assessment;

  if (riskLevel === 'HIGH') {
    return [
      {
        tier: 'Conservative',
        action: t.HIGH,
        reason: 'Highest risk tier — maximum load reduction.',
      },
      {
        tier: 'Moderate',
        action: t.MEDIUM,
        reason: 'Partial cut if the athlete must stay active this week.',
      },
      {
        tier: 'Minimal change',
        action: primaryAction,
        reason: 'Smallest adjustment that still respects elevated risk.',
      },
    ];
  }

  if (riskLevel === 'MEDIUM') {
    return [
      {
        tier: 'Conservative',
        action: t.HIGH,
        reason: 'Play it safe if signals worsen overnight.',
      },
      {
        tier: 'Moderate',
        action: t.MEDIUM,
        reason: 'Matches the primary risk call — reduce intensity, keep volume.',
      },
      {
        tier: 'Minimal change',
        action: primaryAction,
        reason: 'Lightest touch that still acknowledges mixed signals.',
      },
    ];
  }

  // LOW risk
  if (performancePrediction === 'DECLINING') {
    return [
      {
        tier: 'Conservative',
        action: LOW_DECLINING_ACTION,
        reason: 'Risk is low but performance is sliding — deload proactively.',
      },
      {
        tier: 'Moderate',
        action: 'Keep volume but trim one hard session this week.',
        reason: 'Small tweak without a full deload.',
      },
      {
        tier: 'Minimal change',
        action: t.LOW,
        reason: 'Continue as planned with extra sleep and fatigue monitoring.',
      },
    ];
  }

  return [
    {
      tier: 'Conservative',
      action: 'Add an extra easy/recovery day this week.',
      reason: 'Optional buffer even though risk is low.',
    },
    {
      tier: 'Moderate',
      action: t.LOW,
      reason: 'Stay on plan — signals look stable.',
    },
    {
      tier: 'Minimal change',
      action: primaryAction,
      reason: 'No adjustment needed; performance and risk both look fine.',
    },
  ];
}

/**
 * Schema + business-rule gate. Malformed JSON or a full-training plan
 * when risk is MEDIUM/HIGH discards the LLM output entirely.
 */
export function applyGradedLlmResponse(
  raw: string,
  opts: {
    assessment: RiskAssessment;
    sportGroup: SportGroup;
    primaryAction: string;
    defaultActionPercent?: number;
  },
  fallback: () => GradedOptionsResult = () => ({
    options: fallbackGradedOptions(
      opts.assessment,
      opts.sportGroup,
      opts.primaryAction,
      opts.defaultActionPercent,
    ),
    source: 'rules',
  }),
): GradedOptionsResult {
  const parsed = parseGradedOutput(raw, { riskLevel: opts.assessment.riskLevel });
  if (!parsed.ok) {
    logGuardrailFallback('graded', parsed.reason);
    return fallback();
  }
  return { options: parsed.data.options, source: 'llm' };
}

export async function generateGradedOptions(opts: {
  assessment: RiskAssessment;
  sportGroup: SportGroup;
  sport?: string | null;
  primaryAction: string;
  primaryNote: string;
  defaultActionPercent?: number;
}): Promise<GradedOptionsResult> {
  const fallback = (): GradedOptionsResult => ({
    options: fallbackGradedOptions(
      opts.assessment,
      opts.sportGroup,
      opts.primaryAction,
      opts.defaultActionPercent,
    ),
    source: 'rules',
  });

  const apiKey = process.env.ANTHROPIC_API_KEY?.trim();
  if (!apiKey) {
    return fallback();
  }

  const context = [
    `Sport: ${opts.sport ?? 'unspecified'} (group: ${opts.sportGroup})`,
    `Risk level: ${opts.assessment.riskLevel}`,
    `Performance prediction: ${opts.assessment.performancePrediction}`,
    `ACWR: ${opts.assessment.acwr.toFixed(2)}`,
    `7-day load: ${opts.assessment.trainingLoad7d.toFixed(0)}`,
    `Recovery trend: ${opts.assessment.recoveryTrend}`,
    `Risk reason: ${opts.assessment.reason}`,
    `Primary recommendation (orchestrator): ${opts.primaryAction}`,
    `Orchestrator note: ${opts.primaryNote}`,
  ].join('\n');

  try {
    const model = createChatAnthropic({ apiKey, maxTokens: 700 });
    const prompt = ChatPromptTemplate.fromMessages([
      ['system', GRADED_PROMPT],
      ['human', 'Athlete context:\n{context}\n\nReturn the JSON object.'],
    ]);
    const chain = prompt.pipe(model).pipe(new StringOutputParser());
    const raw = await chain.invoke({ context });
    return applyGradedLlmResponse(raw, opts, fallback);
  } catch (err) {
    logger.error('graded options LLM failed', err);
    return fallback();
  }
}
