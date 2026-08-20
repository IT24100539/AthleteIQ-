/**
 * Hybrid explainability (Sections 13.4 and 14.5)
 * =============================================
 *
 * The rule engine in assessRisk() is the source of truth for the
 * classification. It uses fixed, inspectable thresholds (ACWR bands,
 * recovery trend, persistent fatigue) so a coach can always answer
 * "why is this HIGH?" by pointing at a number, not a model weight.
 *
 * The LLM here is a writer, not a judge. After assessRisk() has already
 * locked LOW / MEDIUM / HIGH (and GOOD / AVERAGE / DECLINING), we hand
 * that locked result plus the last 5 check-ins to Claude. Its only job
 * is to turn the multi-day trend into a richer paragraph and, if the
 * days look odd, raise a "worth a closer look" flag.
 *
 * It must never change riskLevel. If the API key is missing, the model
 * times out, or the JSON is garbage, we store the existing plain-text
 * reason and move on. An LLM outage must never block a risk write.
 */

import { StringOutputParser } from '@langchain/core/output_parsers';
import { ChatPromptTemplate } from '@langchain/core/prompts';
import { logger } from 'firebase-functions';
import { createChatAnthropic } from './anthropic';
import { DailyEntry } from './calculations';
import { RiskAssessment } from './riskModel';

export interface ExplainabilityLlmResult {
  riskLevelReasoningLLM: string;
  riskLevelPatternFlag: string | null;
  performanceReasoningLLM: string;
  source: 'llm' | 'rules';
}

/** Literal JSON uses doubled braces so ChatPromptTemplate does not treat keys as variables. */
const EXPLAIN_PROMPT = `You are AthleteIQ's explainability writer (Sections 13.4 / 14.5). A rule-based engine has ALREADY classified this athlete. You do not classify. You explain.

Hard rules:
- The locked riskLevel and performancePrediction below are final. Do not contradict, upgrade, or downgrade them.
- Phrase performance in the sport-group framing given (time/pace, coach-rated readiness, max output, match + readiness, or readiness + sparring). Do not invent a different metric.
- Ground every claim in the provided numbers and the last 5 check-in days. Do not invent metrics.
- riskLevelReasoningLLM: 2–3 sentences that walk through the multi-day trend (load, sleep, fatigue, HRV if present) and why it matches the locked riskLevel.
- riskLevelPatternFlag: null unless the last 5 days show a pattern a coach should glance at (e.g. sleep collapsing while load climbs, fatigue stuck high, HRV dropping). If you flag, start with "Worth a closer look:" and one sentence. This is a note, not a new risk level.
- performanceReasoningLLM: 1–2 interpretive sentences about the locked performance prediction. This one may be more narrative because it is not a safety flag.
- Return JSON only, no markdown:
{{"riskLevelReasoningLLM":"...","riskLevelPatternFlag":null,"performanceReasoningLLM":"..."}}`;

function formatLast5(entriesRecentFirst: DailyEntry[]): string {
  const last5 = entriesRecentFirst.slice(0, 5);
  if (last5.length === 0) return 'No check-ins in the last 5 days.';
  return last5
    .map((e) => {
      const parts = [`${e.date}: fatigue ${e.fatigueScore}/5`, `load ${e.trainingLoad ?? 0}`];
      if (e.sleepHours != null) parts.push(`sleep ${e.sleepHours.toFixed(1)}h`);
      if (e.hrv != null) parts.push(`HRV ${e.hrv}`);
      if (e.restingHeartRate != null) parts.push(`rHR ${e.restingHeartRate}`);
      return `  ${parts.join(', ')}`;
    })
    .join('\n');
}

function fallbackExplanation(assessment: RiskAssessment): ExplainabilityLlmResult {
  return {
    riskLevelReasoningLLM: assessment.reason,
    riskLevelPatternFlag: null,
    performanceReasoningLLM: `Performance is classified ${assessment.performancePrediction} (${assessment.performanceFrame}) from the same session-RPE series (Fitness–Fatigue index and recovery trend).`,
    source: 'rules',
  };
}

function parseExplainJson(raw: string): Omit<ExplainabilityLlmResult, 'source'> | null {
  const trimmed = raw.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  const start = trimmed.indexOf('{');
  const end = trimmed.lastIndexOf('}');
  if (start === -1 || end <= start) return null;
  try {
    const parsed = JSON.parse(trimmed.slice(start, end + 1)) as {
      riskLevelReasoningLLM?: unknown;
      riskLevelPatternFlag?: unknown;
      performanceReasoningLLM?: unknown;
    };
    const riskText =
      typeof parsed.riskLevelReasoningLLM === 'string'
        ? parsed.riskLevelReasoningLLM.trim()
        : '';
    const perfText =
      typeof parsed.performanceReasoningLLM === 'string'
        ? parsed.performanceReasoningLLM.trim()
        : '';
    if (!riskText || !perfText) return null;
    const flagRaw = parsed.riskLevelPatternFlag;
    const flag =
      typeof flagRaw === 'string' && flagRaw.trim() && flagRaw.trim().toLowerCase() !== 'null'
        ? flagRaw.trim()
        : null;
    return {
      riskLevelReasoningLLM: riskText,
      riskLevelPatternFlag: flag,
      performanceReasoningLLM: perfText,
    };
  } catch {
    return null;
  }
}

/**
 * Enrich a locked assessRisk() result with LLM prose. Never mutates
 * riskLevel or performancePrediction. Never throws.
 */
export async function enrichAssessmentExplanation(
  assessment: RiskAssessment,
  entriesRecentFirst: DailyEntry[],
): Promise<ExplainabilityLlmResult> {
  const fallback = fallbackExplanation(assessment);
  const apiKey = process.env.ANTHROPIC_API_KEY?.trim();
  if (!apiKey) {
    return fallback;
  }

  const context = [
    `LOCKED riskLevel: ${assessment.riskLevel} (do not change)`,
    `LOCKED performancePrediction: ${assessment.performancePrediction} (do not change)`,
    `Sport-group framing (Section 12.3): ${assessment.performanceFrameAxis} → ${assessment.performanceFrame}`,
    `Rule-based reason: ${assessment.reason}`,
    `Confidence: ${assessment.confidence}`,
    `ACWR: ${assessment.acwr.toFixed(2)}`,
    `7-day load: ${assessment.trainingLoad7d.toFixed(0)}`,
    `28-day avg weekly load: ${assessment.trainingLoad28dAvg.toFixed(0)}`,
    `Recovery trend: ${assessment.recoveryTrend}`,
    `Last 5 check-ins (most recent first):\n${formatLast5(entriesRecentFirst)}`,
  ].join('\n');

  try {
    const model = createChatAnthropic({ apiKey, maxTokens: 500 });
    const prompt = ChatPromptTemplate.fromMessages([
      ['system', EXPLAIN_PROMPT],
      ['human', '{context}'],
    ]);
    const chain = prompt.pipe(model).pipe(new StringOutputParser());
    const raw = await chain.invoke({ context });
    const parsed = parseExplainJson(raw);
    if (!parsed) {
      logger.warn('explainability LLM: invalid JSON, using rule-based reason');
      return fallback;
    }
    return { ...parsed, source: 'llm' };
  } catch (err) {
    logger.warn('explainability LLM failed; using rule-based reason', err);
    return fallback;
  }
}
