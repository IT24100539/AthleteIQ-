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
import { assessRisk } from './riskModel';
import {
  buildRecommendation,
  recommendationOptions,
  Recommendation,
  SportGroup,
} from './recommendationEngine';
import { invokeOrchestratorTool, ORCHESTRATOR_TOOL_DEFS } from './orchestratorTools';

export const ORCHESTRATOR_SYSTEM_PROMPT = `You are AthleteIQ's Orchestrator. You decide the training recommendation a coach will review.

HARD SAFETY CONSTRAINT (never violate):
- Protecting the athlete comes first.
- If there is genuine ambiguity OR elevated risk (MEDIUM or HIGH), prioritize athlete safety over performance optimization. Never the reverse.
- A strong performance prediction must not override a MEDIUM or HIGH risk call. You may acknowledge that performance looks good, but the action must still reduce load or intensity.
- Only recommend "continue training as planned" when risk is LOW and there is no serious ambiguity in the signals.

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

function parseAgentJson(raw: string): { action?: string; orchestratorNote?: string; why?: string } | null {
  const trimmed = raw.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  const start = trimmed.indexOf('{');
  const end = trimmed.lastIndexOf('}');
  if (start === -1 || end <= start) return null;
  try {
    return JSON.parse(trimmed.slice(start, end + 1)) as {
      action?: string;
      orchestratorNote?: string;
      why?: string;
    };
  } catch {
    return null;
  }
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

function looksLikeFullTraining(action: string): boolean {
  const a = action.toLowerCase();
  return (
    a.includes('continue training as planned') ||
    a.includes('train as planned') ||
    a.includes('full intensity') ||
    a.includes('no change')
  );
}

export async function runOrchestratorAgent(opts: {
  athleteUid: string;
  sportGroup: SportGroup;
  defaultActionPercent?: number;
  loadEntries?: CheckInLoader;
  persistTrace?: boolean;
}): Promise<OrchestratorResult> {
  const loadEntries = opts.loadEntries ?? loadCheckIns;
  const entries = await loadEntries(opts.athleteUid, 35);
  const assessment = assessRisk(entries, opts.sportGroup);
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

  const apiKey = process.env.ANTHROPIC_API_KEY?.trim();
  if (!apiKey) {
    return fallback([], 'ANTHROPIC_API_KEY missing — used rule-based Orchestrator.');
  }
  if (entries.length < 5) {
    return fallback([], 'Fewer than 5 check-ins — used rule-based Orchestrator.');
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
      const response = await model.invoke(messages);
      messages.push(response);
      const calls = response.tool_calls ?? [];
      if (calls.length === 0) {
        const parsed = parseAgentJson(messageText(response.content));
        if (!parsed?.action || !parsed.orchestratorNote) {
          const result = fallback(trace, 'Agent output was not valid JSON — used rule-based Orchestrator.');
          if (opts.persistTrace !== false) await persistTrace(opts.athleteUid, result);
          return result;
        }

        let action = parsed.action.trim();
        if (!allowed.includes(action)) {
          const match = allowed.find((a) => a.toLowerCase() === action.toLowerCase());
          action = match ?? ruleBased.action;
        }

        let safetyOverride = false;
        if (
          (assessment.riskLevel === 'HIGH' || assessment.riskLevel === 'MEDIUM') &&
          looksLikeFullTraining(action)
        ) {
          safetyOverride = true;
          action = ruleBased.action;
        }

        const decided: OrchestratorResult = {
          action,
          orchestratorNote: safetyOverride
            ? `${parsed.orchestratorNote} [Safety override: elevated risk cannot yield a full-training plan.]`
            : parsed.orchestratorNote,
          source: 'agent',
          safetyOverride,
          ruleBased,
          agreedWithRules: action === ruleBased.action,
          trace: [
            ...trace,
            {
              order: trace.length + 1,
              type: 'decision',
              why: parsed.why ?? parsed.orchestratorNote,
            },
          ],
        };

        if (opts.persistTrace !== false) await persistTrace(opts.athleteUid, decided);
        return decided;
      }

      for (const call of calls) {
        const output = await invokeOrchestratorTool(
          call.name,
          (call.args ?? {}) as Record<string, unknown>,
          loadEntries,
        );
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
    return result;
  } catch (err) {
    logger.error('orchestrator agent failed', err);
    const result = fallback(trace, `Agent error: ${err instanceof Error ? err.message : String(err)}`);
    if (opts.persistTrace !== false) await persistTrace(opts.athleteUid, result);
    return result;
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
