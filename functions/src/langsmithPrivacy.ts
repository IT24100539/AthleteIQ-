/**
 * What may (and must not) be sent to LangSmith.
 *
 * Automatic LangChain tracing is disabled: it would upload full prompts,
 * including athlete IDs, ACWR, sleep, HRV, fatigue, and pain notes.
 * Dev traces are built from this allowlist only; anything else is dropped.
 */

export const LANGSMITH_REDACT = '[redacted]';

/** Keys that must never appear in a LangSmith payload (deny-list, defense in depth). */
export const LANGSMITH_NEVER_SEND_KEYS = [
  'athleteUid',
  'athleteId',
  'athleteName',
  'callerUid',
  'callerName',
  'uid',
  'userId',
  'name',
  'email',
  'fcmToken',
  'pain',
  'painNotes',
  'painReport',
  'areas',
  'soreness',
  'notes',
  'sleepHours',
  'sleep',
  'hrv',
  'restingHeartRate',
  'rhr',
  'fatigueScore',
  'fatigue',
  'trainingLoad',
  'trainingLoad7d',
  'trainingLoad28dAvg',
  'acwr',
  'checkins',
  'checkIn',
  'entries',
  'recommendation',
  'orchestratorNote',
  'ruleBasedNote',
  'why',
  'action',
  'reason',
  'riskLevel',
  'performancePrediction',
  'performanceFrame',
  'recoveryTrend',
  'riskLevelReasoningLLM',
  'performanceReasoningLLM',
  'note',
  'query',
  'context',
  'prompt',
  'messages',
  'human',
  'content',
  'output',
  'input',
  'raw',
  'text',
  'pageContent',
] as const;

const NEVER = new Set<string>(LANGSMITH_NEVER_SEND_KEYS);

/** Fields we intentionally send. Everything else is omitted. */
export const LANGSMITH_ALLOWED_KEYS = [
  'surface',
  'sportGroup',
  'toolCalls',
  'tool',
  'ok',
  'latencyMs',
  'llmRoundtrips',
  'llmLatencyMs',
  'retrieveLatencyMs',
  'totalLatencyMs',
  'schemaValidationFailed',
  'schemaFailureReason',
  'fallbackTriggered',
  'fallbackReason',
  'source',
  'agreedWithRules',
  'retrievedTags',
  'retrievedCount',
  'privacy',
] as const;

const ALLOWED = new Set<string>(LANGSMITH_ALLOWED_KEYS);

const UID_RE = /\b[A-Za-z0-9]{20,}\b/g;
const EMAIL_RE = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi;
const ISO_DATE_RE = /\b\d{4}-\d{2}-\d{2}(?:[T\s]\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?Z?)?\b/g;
const ACWR_RE = /\bACWR\s*[:=]?\s*\d+(\.\d+)?\b/gi;
const LOAD_RE = /\b(training\s*load|7-day load|sleep|HRV|fatigue|rHR)\s*[:=]?\s*\d+(\.\d+)?\b/gi;
const ATHLETE_ID_ASSIGN_RE = /\bathleteId\s*=\s*"[^"]+"/gi;

export function sanitizeLangSmithString(value: string): string {
  return value
    .replace(ATHLETE_ID_ASSIGN_RE, 'athleteId="[redacted]"')
    .replace(EMAIL_RE, '[redacted-email]')
    .replace(UID_RE, '[redacted-id]')
    .replace(ISO_DATE_RE, '[redacted-date]')
    .replace(ACWR_RE, 'ACWR [redacted]')
    .replace(LOAD_RE, '$1 [redacted]');
}

/**
 * Drop denied keys, keep allowlisted keys, scrub leftover strings.
 * Used as a last pass before Client.createRun so a future caller cannot
 * accidentally attach a raw assessment object.
 */
export function scrubForLangSmith(value: unknown, depth = 0): unknown {
  if (depth > 8) return LANGSMITH_REDACT;
  if (value == null) return value;
  if (typeof value === 'string') return sanitizeLangSmithString(value);
  if (typeof value === 'number' || typeof value === 'boolean') return value;
  if (Array.isArray(value)) return value.map((v) => scrubForLangSmith(v, depth + 1));
  if (typeof value !== 'object') return LANGSMITH_REDACT;

  const out: Record<string, unknown> = {};
  for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
    if (NEVER.has(key)) {
      continue;
    }
    if (depth === 0 && !ALLOWED.has(key)) {
      continue;
    }
    out[key] = scrubForLangSmith(nested, depth + 1);
  }
  return out;
}

export interface RedactedToolCall {
  tool: string;
  ok: boolean;
  latencyMs: number;
}

export interface RedactedOrchestratorTrace {
  surface: 'orchestrator';
  privacy: 'redacted_no_phi';
  sportGroup: string;
  toolCalls: RedactedToolCall[];
  llmRoundtrips: number;
  llmLatencyMs: number;
  totalLatencyMs: number;
  schemaValidationFailed: boolean;
  schemaFailureReason: string | null;
  fallbackTriggered: boolean;
  fallbackReason: string | null;
  source: 'agent' | 'rules_fallback';
  agreedWithRules: boolean;
}

export interface RedactedKnowledgeTrace {
  surface: 'knowledge_agent';
  privacy: 'redacted_no_phi';
  retrievedTags: string[];
  retrievedCount: number;
  retrieveLatencyMs: number;
  llmLatencyMs: number;
  totalLatencyMs: number;
  schemaValidationFailed: boolean;
  schemaFailureReason: string | null;
  fallbackTriggered: boolean;
  fallbackReason: string | null;
  source: 'llm' | 'retrieved';
}

export function buildOrchestratorLangSmithPayload(
  raw: RedactedOrchestratorTrace,
): RedactedOrchestratorTrace {
  return scrubForLangSmith(raw) as RedactedOrchestratorTrace;
}

export function buildKnowledgeLangSmithPayload(
  raw: RedactedKnowledgeTrace,
): RedactedKnowledgeTrace {
  return scrubForLangSmith(raw) as RedactedKnowledgeTrace;
}

export function classifyOrchestratorFallback(why: string | undefined): {
  schemaValidationFailed: boolean;
  schemaFailureReason: string | null;
  fallbackReason: string | null;
} {
  if (!why) {
    return { schemaValidationFailed: false, schemaFailureReason: null, fallbackReason: null };
  }
  const rejected = why.match(/rejected \(([^)]+)\)/);
  if (rejected) {
    return {
      schemaValidationFailed: true,
      schemaFailureReason: sanitizeLangSmithString(rejected[1]),
      fallbackReason: 'schema_or_business_rule',
    };
  }
  if (/ANTHROPIC_API_KEY/i.test(why)) {
    return {
      schemaValidationFailed: false,
      schemaFailureReason: null,
      fallbackReason: 'missing_api_key',
    };
  }
  if (/Fewer than 5/i.test(why)) {
    return {
      schemaValidationFailed: false,
      schemaFailureReason: null,
      fallbackReason: 'insufficient_checkins',
    };
  }
  if (/tool-call limit/i.test(why)) {
    return {
      schemaValidationFailed: false,
      schemaFailureReason: null,
      fallbackReason: 'tool_call_limit',
    };
  }
  if (/Agent error/i.test(why)) {
    return {
      schemaValidationFailed: false,
      schemaFailureReason: null,
      fallbackReason: 'llm_error',
    };
  }
  return {
    schemaValidationFailed: false,
    schemaFailureReason: null,
    fallbackReason: sanitizeLangSmithString(why).slice(0, 120),
  };
}
