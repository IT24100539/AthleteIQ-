/**
 * LangChain tool-calling Orchestrator (Section 6).
 * Uses ChatAnthropic.bindTools (same stack as Phase E2) rather than
 * AgentExecutor, which pulls a type graph that OOMs `tsc` on this repo.
 *
 * Safety constraint is in the system prompt and re-checked after the
 * model returns: elevated risk may never lose to performance.
 */

import { AIMessage, HumanMessage, SystemMessage, ToolMessage } from '@langchain/core/messages';
import { createChatAnthropic } from './anthropic';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { CheckInLoader, loadCheckIns } from './checkInLoader';
import { assessRisk, RiskLevel } from './riskModel';
import {
  buildRecommendation,
  recommendationOptions,
  Recommendation,
  SportGroup,
} from './recommendationEngine';
import { invokeOrchestratorTool, ORCHESTRATOR_TOOL_DEFS } from './orchestratorTools';
import {
  MEDICAL_DISCLAIMER,
  RISK_OVERRIDES_PERFORMANCE_CLAUSE,
  TOOL_GROUNDING_INSTRUCTION,
} from './promptFragments';
import { logGuardrailFallback, parseOrchestratorOutput } from './llmGuardrails';
import { classifyOrchestratorFallback } from './langsmithPrivacy';
import { traceOrchestratorToLangSmith } from './langsmithDevTrace';

export const ORCHESTRATOR_SYSTEM_PROMPT = `You are AthleteIQ's Orchestrator. You decide the training recommendation a coach will review.

${RISK_OVERRIDES_PERFORMANCE_CLAUSE}

${MEDICAL_DISCLAIMER}

${TOOL_GROUNDING_INSTRUCTION}

How to work:
1. Call getRiskAssessment and getPerformancePrediction. Call getAthleteHistory if the summaries are thin or conflicting.
2. Choose ONE action from the allowed list for this sport. Do not invent a new plan.
3. Reply with JSON only, no markdown:
{"action":"...","orchestratorNote":"...","why":"..."}
- action: exact string from the allowed list
- orchestratorNote: one sentence for the coach
- why: one sentence on which tools mattered and why safety or performance won`;

export interface OrchestratorTraceStep {
  order: number;
  type: 'tool' | 'decision';
  tool?: string;
  input?: unknown;
  output?: string;
  why?: string;
}

export interface OrchestratorResult {
  action: string;
  orchestratorNote: string;
  source: 'agent' | 'rules_fallback';
  safetyOverride: boolean;
  ruleBased: Recommendation;
  agreedWithRules: boolean;
  trace: OrchestratorTraceStep[];
}

function messageText(content: unknown): string {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content
      .map((part) => {
        if (typeof part === 'string') return part;
        if (part && typeof part === 'object' && 'text' in part) {
          return String((part as { text?: string }).text ?? '');
        }
        return '';
      })
      .join('');
  }
  return String(content ?? '');
}

/**
 * Zod + business-rule gate for an Orchestrator JSON reply. On any failure,
 * returns the same rules_fallback result used when the API is down.
 */
export function applyOrchestratorLlmResponse(
  raw: string,
  opts: {
    allowedActions: string[];
    riskLevel: RiskLevel;
    ruleBased: Recommendation;
    trace: OrchestratorTraceStep[];
  },
): OrchestratorResult {
  const fallback = (reason: string): OrchestratorResult => {
    logGuardrailFallback('orchestrator', reason);
    return {
      action: opts.ruleBased.action,
      orchestratorNote: opts.ruleBased.orchestratorNote,
      source: 'rules_fallback',
      safetyOverride: false,
      ruleBased: opts.ruleBased,
      agreedWithRules: true,
      trace: [...opts.trace, { order: opts.trace.length + 1, type: 'decision', why: reason }],
    };
  };

  const parsed = parseOrchestratorOutput(raw, {
    allowedActions: opts.allowedActions,
    riskLevel: opts.riskLevel,
  });
  if (!parsed.ok) {
    return fallback(`Agent output rejected (${parsed.reason}) — used rule-based Orchestrator.`);
  }

  return {
    action: parsed.data.action,
    orchestratorNote: parsed.data.orchestratorNote,
    source: 'agent',
    safetyOverride: false,
    ruleBased: opts.ruleBased,
    agreedWithRules: parsed.data.action === opts.ruleBased.action,
    trace: [
      ...opts.trace,
      {
        order: opts.trace.length + 1,
        type: 'decision',
        why: parsed.data.why ?? parsed.data.orchestratorNote,
      },
    ],
  };
}

export async function runOrchestratorAgent(opts: {
  athleteUid: string;
  sportGroup: SportGroup;
  defaultActionPercent?: number;
  loadEntries?: CheckInLoader;
  persistTrace?: boolean;
  asOf?: string;
}): Promise<OrchestratorResult> {
  const started = Date.now();
  let llmLatencyMs = 0;
  let llmRoundtrips = 0;
  const toolCalls: { tool: string; ok: boolean; latencyMs: number }[] = [];

  const loadEntries = opts.loadEntries ?? loadCheckIns;
  const entries = await loadEntries(opts.athleteUid, 35);
  const assessment = assessRisk(entries, opts.sportGroup, opts.asOf);
  const pct = opts.defaultActionPercent;
  const ruleBased = buildRecommendation(
    assessment.riskLevel,
    assessment.performancePrediction,
    opts.sportGroup,
    pct,
  );
  const options = recommendationOptions(opts.sportGroup, pct);
  const allowed = [options.HIGH, options.MEDIUM, options.LOW, options.LOW_DECLINING];

  const fallback = (trace: OrchestratorTraceStep[], reason: string): OrchestratorResult => ({
    action: ruleBased.action,
    orchestratorNote: ruleBased.orchestratorNote,
    source: 'rules_fallback',
    safetyOverride: false,
    ruleBased,
    agreedWithRules: true,
    trace: [
      ...trace,
      { order: trace.length + 1, type: 'decision', why: reason },
    ],
  });

  const finish = async (result: OrchestratorResult): Promise<OrchestratorResult> => {
    const lastWhy = result.trace[result.trace.length - 1]?.why;
    const classified = classifyOrchestratorFallback(
      result.source === 'rules_fallback' ? lastWhy : undefined,
    );
    await traceOrchestratorToLangSmith({
      surface: 'orchestrator',
      privacy: 'redacted_no_phi',
      sportGroup: opts.sportGroup,
      toolCalls,
      llmRoundtrips,
      llmLatencyMs,
      totalLatencyMs: Date.now() - started,
      schemaValidationFailed: classified.schemaValidationFailed,
      schemaFailureReason: classified.schemaFailureReason,
      fallbackTriggered: result.source === 'rules_fallback',
      fallbackReason:
        result.source === 'rules_fallback' ? classified.fallbackReason : null,
      source: result.source,
      agreedWithRules: result.agreedWithRules,
    });
    return result;
  };

  const apiKey = process.env.ANTHROPIC_API_KEY?.trim();
  if (!apiKey) {
    return finish(fallback([], 'ANTHROPIC_API_KEY missing — used rule-based Orchestrator.'));
  }
  if (entries.length < 5) {
    return finish(fallback([], 'Fewer than 5 check-ins — used rule-based Orchestrator.'));
  }

  const model = createChatAnthropic({
    apiKey,
    maxTokens: 600,
  }).bindTools(ORCHESTRATOR_TOOL_DEFS);

  const input = [
    `Decide the recommendation for athleteId="${opts.athleteUid}".`,
    `Sport group: ${opts.sportGroup}.`,
    'Allowed actions (pick one exactly):',
    `- HIGH: ${options.HIGH}`,
    `- MEDIUM: ${options.MEDIUM}`,
    `- LOW: ${options.LOW}`,
    `- LOW + declining performance: ${options.LOW_DECLINING}`,
    'Call tools with this athleteId. Then return the JSON object.',
  ].join('\n');

  const messages: Array<SystemMessage | HumanMessage | AIMessage | ToolMessage> = [
    new SystemMessage(ORCHESTRATOR_SYSTEM_PROMPT),
    new HumanMessage(input),
  ];
  const trace: OrchestratorTraceStep[] = [];

  try {
    for (let i = 0; i < 6; i++) {
      const llmStart = Date.now();
      const response = await model.invoke(messages);
      llmLatencyMs += Date.now() - llmStart;
      llmRoundtrips += 1;
      messages.push(response);
      const calls = response.tool_calls ?? [];
      if (calls.length === 0) {
        const decided = applyOrchestratorLlmResponse(messageText(response.content), {
          allowedActions: allowed,
          riskLevel: assessment.riskLevel,
          ruleBased,
          trace,
        });
        if (opts.persistTrace !== false) await persistTrace(opts.athleteUid, decided);
        return finish(decided);
      }

      for (const call of calls) {
        const toolStart = Date.now();
        let ok = true;
        let output: string;
        try {
          output = await invokeOrchestratorTool(
            call.name,
            (call.args ?? {}) as Record<string, unknown>,
            loadEntries,
            opts.athleteUid,
          );
        } catch {
          ok = false;
          output = JSON.stringify({ error: 'tool_failed' });
        }
        toolCalls.push({
          tool: call.name,
          ok,
          latencyMs: Date.now() - toolStart,
        });
        trace.push({
          order: trace.length + 1,
          type: 'tool',
          tool: call.name,
          input: call.args,
          output: output.slice(0, 2000),
          why: `Called ${call.name} to ground the decision in computed signals.`,
        });
        messages.push(
          new ToolMessage({
            content: output,
            tool_call_id: call.id ?? `${call.name}-${trace.length}`,
          }),
        );
      }
    }

    const result = fallback(trace, 'Agent hit the tool-call limit — used rule-based Orchestrator.');
    if (opts.persistTrace !== false) await persistTrace(opts.athleteUid, result);
    return finish(result);
  } catch (err) {
    logger.error('orchestrator agent failed', err);
    const result = fallback(trace, `Agent error: ${err instanceof Error ? err.message : String(err)}`);
    if (opts.persistTrace !== false) await persistTrace(opts.athleteUid, result);
    return finish(result);
  }
}

async function persistTrace(athleteUid: string, result: OrchestratorResult): Promise<void> {
  try {
    const db = getFirestore();
    await db
      .collection('athletes')
      .doc(athleteUid)
      .collection('orchestratorTraces')
      .add({
        decidedAt: new Date().toISOString(),
        source: result.source,
        action: result.action,
        orchestratorNote: result.orchestratorNote,
        ruleBasedAction: result.ruleBased.action,
        ruleBasedNote: result.ruleBased.orchestratorNote,
        agreedWithRules: result.agreedWithRules,
        safetyOverride: result.safetyOverride,
        trace: result.trace,
      });
  } catch (err) {
    logger.warn('could not persist orchestrator trace', err);
  }
}
