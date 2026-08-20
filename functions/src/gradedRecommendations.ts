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
import { RiskAssessment, RiskLevel } from './riskModel';

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

/** Literal JSON uses doubled braces so ChatPromptTemplate does not treat keys as variables. */
const GRADED_PROMPT = `You are AthleteIQ's recommendation writer (Section 16.3). Given an athlete's risk signals and sport, produce exactly 3 graded training options for a coach to choose from.

Tiers (always use these exact labels):
1. Conservative — maximum load reduction; safest choice when risk is elevated.
2. Moderate — balanced adjustment; partial reduction while keeping some structure.
3. Minimal change — smallest adjustment that still acknowledges the risk/performance signals.

Rules:
- Each option needs a one-line "reason" (max 20 words).
- Wording must fit the sport group provided.
- If risk is HIGH or MEDIUM, Minimal change must NOT be full unrestricted training — never "train as hard as planned" when risk is elevated.
- If risk is LOW, Minimal change may be "continue as planned".
- Return JSON only, no markdown:
{{"options":[{{"tier":"Conservative","action":"...","reason":"..."}},{{"tier":"Moderate","action":"...","reason":"..."}},{{"tier":"Minimal change","action":"...","reason":"..."}}]}}`;

function parseGradedJson(raw: string): GradedOption[] | null {
  const trimmed = raw.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  const start = trimmed.indexOf('{');
  const end = trimmed.lastIndexOf('}');
  if (start === -1 || end <= start) return null;
  try {
    const parsed = JSON.parse(trimmed.slice(start, end + 1)) as { options?: GradedOption[] };
    if (!Array.isArray(parsed.options) || parsed.options.length < 2) return null;
    const validTiers: GradedOptionTier[] = ['Conservative', 'Moderate', 'Minimal change'];
    const options = parsed.options
      .filter(
        (o) =>
          o &&
          validTiers.includes(o.tier as GradedOptionTier) &&
          typeof o.action === 'string' &&
          typeof o.reason === 'string',
      )
      .slice(0, 3)
      .map((o) => ({
        tier: o.tier as GradedOptionTier,
        action: o.action.trim(),
        reason: o.reason.trim(),
      }));
    return options.length >= 2 ? options : null;
  } catch {
    return null;
  }
}

function looksLikeFullTraining(action: string): boolean {
  const a = action.toLowerCase();
  return a.includes('continue training as planned') || a.includes('train as planned');
}

function enforceSafety(
  options: GradedOption[],
  riskLevel: RiskLevel,
  templates: ReturnType<typeof buildSportTemplates>,
): GradedOption[] {
  if (riskLevel !== 'HIGH' && riskLevel !== 'MEDIUM') return options;
  return options.map((o) => {
    if (o.tier === 'Minimal change' && looksLikeFullTraining(o.action)) {
      const template = templates.other;
      return {
        ...o,
        action: template.MEDIUM,
        reason: `${o.reason} (adjusted: elevated risk cannot allow full training.)`,
      };
    }
    return o;
  });
}

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

export async function generateGradedOptions(opts: {
  assessment: RiskAssessment;
  sportGroup: SportGroup;
  sport?: string | null;
  primaryAction: string;
  primaryNote: string;
  defaultActionPercent?: number;
}): Promise<GradedOptionsResult> {
  const templates = buildSportTemplates(opts.defaultActionPercent);
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
    const parsed = parseGradedJson(raw);
    if (!parsed) {
      logger.warn('graded options: invalid LLM JSON, using rules fallback');
      return fallback();
    }
    return {
      options: enforceSafety(parsed, opts.assessment.riskLevel, templates),
      source: 'llm',
    };
  } catch (err) {
    logger.error('graded options LLM failed', err);
    return fallback();
  }
}
