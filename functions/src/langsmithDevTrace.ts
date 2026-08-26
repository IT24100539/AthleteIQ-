/**
 * Opt-in LangSmith traces for Orchestrator + Knowledge Agent (dev/demo).
 *
 * Enable with LANGSMITH_TRACING=true and LANGSMITH_API_KEY.
 * Do **not** set LANGCHAIN_TRACING_V2 — that would upload raw prompts.
 */

import { randomUUID } from 'crypto';
import { logger } from 'firebase-functions';
import { Client } from 'langsmith';
import {
  buildKnowledgeLangSmithPayload,
  buildOrchestratorLangSmithPayload,
  RedactedKnowledgeTrace,
  RedactedOrchestratorTrace,
} from './langsmithPrivacy';

/** Kill automatic LangChain→LangSmith prompt upload (PHI leak). */
export function disableLangChainAutoTracing(): void {
  process.env.LANGCHAIN_TRACING_V2 = 'false';
  process.env.LANGCHAIN_TRACING = 'false';
}

disableLangChainAutoTracing();

export type LangSmithTestSink = (payload: {
  name: string;
  runType: string;
  inputs: Record<string, unknown>;
  outputs: Record<string, unknown>;
}) => void | Promise<void>;

let testSink: LangSmithTestSink | null = null;
let client: Client | null = null;

export function setLangSmithTestSink(sink: LangSmithTestSink | null): void {
  testSink = sink;
}

export function isLangSmithDevTracingEnabled(): boolean {
  if (process.env.LANGSMITH_TRACING !== 'true') return false;
  if (testSink) return true;
  return Boolean(process.env.LANGSMITH_API_KEY?.trim());
}

function getClient(): Client | null {
  const key = process.env.LANGSMITH_API_KEY?.trim();
  if (!key) return null;
  if (!client) {
    client = new Client({
      apiKey: key,
      apiUrl: process.env.LANGSMITH_ENDPOINT?.trim() || undefined,
      hideInputs: false,
      hideOutputs: false,
    });
  }
  return client;
}

async function postRun(
  name: string,
  payload: Record<string, unknown>,
): Promise<void> {
  if (!isLangSmithDevTracingEnabled()) return;
  const body = {
    name,
    runType: 'chain',
    inputs: { surface: payload.surface, privacy: payload.privacy },
    outputs: payload,
  };
  try {
    if (testSink) {
      await testSink(body);
      return;
    }
    const ls = getClient();
    if (!ls) return;
    const id = randomUUID();
    const now = Date.now();
    await ls.createRun({
      id,
      name,
      run_type: 'chain',
      start_time: now - Number(payload.totalLatencyMs ?? 0),
      end_time: now,
      project_name: process.env.LANGSMITH_PROJECT?.trim() || 'athleteiq-dev',
      extra: {
        metadata: {
          privacy: 'redacted_no_phi',
          note: 'No athlete IDs, names, pain notes, or health metrics.',
        },
      },
      inputs: body.inputs,
      outputs: body.outputs,
    });
  } catch (err) {
    logger.warn('langsmith: failed to post redacted trace (non-fatal)', err);
  }
}

export async function traceOrchestratorToLangSmith(
  raw: RedactedOrchestratorTrace,
): Promise<void> {
  const payload = buildOrchestratorLangSmithPayload(raw);
  await postRun('orchestrator', payload as unknown as Record<string, unknown>);
}

export async function traceKnowledgeToLangSmith(
  raw: RedactedKnowledgeTrace,
): Promise<void> {
  const payload = buildKnowledgeLangSmithPayload(raw);
  await postRun('knowledge_agent', payload as unknown as Record<string, unknown>);
}
