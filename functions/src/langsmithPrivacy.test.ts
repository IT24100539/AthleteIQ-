/**
 * Privacy contract for LangSmith: assert exactly what is stripped vs kept.
 * These tests are the review surface for "would this send health data?"
 */

import assert from 'node:assert/strict';
import { describe, it, beforeEach, afterEach } from 'node:test';
import {
  buildKnowledgeLangSmithPayload,
  buildOrchestratorLangSmithPayload,
  classifyOrchestratorFallback,
  LANGSMITH_ALLOWED_KEYS,
  LANGSMITH_NEVER_SEND_KEYS,
  LANGSMITH_REDACT,
  sanitizeLangSmithString,
  scrubForLangSmith,
} from './langsmithPrivacy';
import {
  isLangSmithDevTracingEnabled,
  setLangSmithTestSink,
  traceKnowledgeToLangSmith,
  traceOrchestratorToLangSmith,
} from './langsmithDevTrace';

describe('LangSmith privacy — keys that must never be sent', () => {
  it('deny-list includes athlete identity, pain, and health metrics', () => {
    const never = new Set<string>(LANGSMITH_NEVER_SEND_KEYS);
    for (const key of [
      'athleteUid',
      'athleteId',
      'athleteName',
      'name',
      'email',
      'pain',
      'painNotes',
      'soreness',
      'sleepHours',
      'hrv',
      'restingHeartRate',
      'fatigueScore',
      'trainingLoad',
      'acwr',
      'checkins',
      'entries',
      'recommendation',
      'orchestratorNote',
      'reason',
      'riskLevel',
      'note',
      'query',
      'messages',
      'pageContent',
    ]) {
      assert.equal(never.has(key), true, `missing deny-list key: ${key}`);
    }
  });

  it('allow-list is only operational metadata (no PHI)', () => {
    const allowed = [...LANGSMITH_ALLOWED_KEYS];
    assert.deepEqual(
      allowed.sort(),
      [
        'agreedWithRules',
        'fallbackReason',
        'fallbackTriggered',
        'latencyMs',
        'llmLatencyMs',
        'llmRoundtrips',
        'ok',
        'privacy',
        'retrieveLatencyMs',
        'retrievedCount',
        'retrievedTags',
        'schemaFailureReason',
        'schemaValidationFailed',
        'source',
        'sportGroup',
        'surface',
        'tool',
        'toolCalls',
        'totalLatencyMs',
      ].sort(),
    );
  });

  it('scrub drops athlete IDs, names, pain notes, and health fields', () => {
    const leaked = {
      surface: 'orchestrator',
      privacy: 'redacted_no_phi',
      sportGroup: 'endurance',
      athleteUid: '7o54AyrYprTUyTJzpKzXdz90lH33',
      athleteName: 'Alex Rivera',
      acwr: 1.62,
      sleepHours: 5.5,
      hrv: 42,
      fatigueScore: 5,
      trainingLoad: 900,
      painNotes: 'sharp stabbing pain after a pop',
      reason: 'ACWR 1.62 with worsening recovery',
      orchestratorNote: 'Alex should rest — ACWR 1.62',
      fallbackTriggered: true,
      fallbackReason: 'schema_or_business_rule',
      schemaValidationFailed: true,
      schemaFailureReason: 'malformed_json',
      toolCalls: [{ tool: 'getRiskAssessment', ok: true, latencyMs: 12 }],
      llmRoundtrips: 2,
      llmLatencyMs: 800,
      totalLatencyMs: 950,
      source: 'rules_fallback',
      agreedWithRules: true,
    };
    const scrubbed = scrubForLangSmith(leaked) as Record<string, unknown>;
    assert.equal('athleteUid' in scrubbed, false);
    assert.equal('athleteName' in scrubbed, false);
    assert.equal('acwr' in scrubbed, false);
    assert.equal('sleepHours' in scrubbed, false);
    assert.equal('hrv' in scrubbed, false);
    assert.equal('fatigueScore' in scrubbed, false);
    assert.equal('trainingLoad' in scrubbed, false);
    assert.equal('painNotes' in scrubbed, false);
    assert.equal('reason' in scrubbed, false);
    assert.equal('orchestratorNote' in scrubbed, false);
    assert.equal(scrubbed.sportGroup, 'endurance');
    assert.equal(scrubbed.fallbackTriggered, true);
    assert.equal(scrubbed.schemaValidationFailed, true);
    assert.equal(JSON.stringify(scrubbed).includes('Alex'), false);
    assert.equal(JSON.stringify(scrubbed).includes('7o54AyrYprTUyTJzpKzXdz90lH33'), false);
    assert.equal(JSON.stringify(scrubbed).includes('stabbing'), false);
    assert.equal(JSON.stringify(scrubbed).includes('1.62'), false);
  });

  it('string sanitizer strips UIDs, emails, dates, and ACWR numbers', () => {
    const dirty =
      'athleteId="7o54AyrYprTUyTJzpKzXdz90lH33" demo.athlete@athleteiq.app ACWR 1.55 sleep 4 on 2026-08-21';
    const clean = sanitizeLangSmithString(dirty);
    assert.equal(clean.includes('7o54AyrYprTUyTJzpKzXdz90lH33'), false);
    assert.equal(clean.includes('demo.athlete@athleteiq.app'), false);
    assert.equal(clean.includes('1.55'), false);
    assert.equal(clean.includes('2026-08-21'), false);
    assert.match(clean, /athleteId="\[redacted\]"/);
  });
});

describe('LangSmith payload builders', () => {
  it('orchestrator payload keeps tools, latency, schema fail, fallback — not health', () => {
    const payload = buildOrchestratorLangSmithPayload({
      surface: 'orchestrator',
      privacy: 'redacted_no_phi',
      sportGroup: 'endurance',
      toolCalls: [
        { tool: 'getRiskAssessment', ok: true, latencyMs: 10 },
        { tool: 'getPerformancePrediction', ok: true, latencyMs: 8 },
      ],
      llmRoundtrips: 2,
      llmLatencyMs: 1200,
      totalLatencyMs: 1400,
      schemaValidationFailed: true,
      schemaFailureReason: 'business:action_not_in_allowed_list',
      fallbackTriggered: true,
      fallbackReason: 'schema_or_business_rule',
      source: 'rules_fallback',
      agreedWithRules: true,
    });
    assert.equal(payload.surface, 'orchestrator');
    assert.equal(payload.toolCalls.length, 2);
    assert.equal(payload.toolCalls[0].tool, 'getRiskAssessment');
    assert.equal(payload.schemaValidationFailed, true);
    assert.equal(payload.fallbackTriggered, true);
    assert.equal(payload.totalLatencyMs, 1400);
    assert.equal('athleteUid' in payload, false);
    assert.equal('acwr' in payload, false);
  });

  it('knowledge payload keeps corpus tags and fallback flags — not assessment numbers', () => {
    const payload = buildKnowledgeLangSmithPayload({
      surface: 'knowledge_agent',
      privacy: 'redacted_no_phi',
      retrievedTags: ['ACWR', 'Banister'],
      retrievedCount: 2,
      retrieveLatencyMs: 15,
      llmLatencyMs: 400,
      totalLatencyMs: 430,
      schemaValidationFailed: true,
      schemaFailureReason: 'malformed_json',
      fallbackTriggered: true,
      fallbackReason: 'schema_or_business_rule',
      source: 'retrieved',
    });
    assert.deepEqual(payload.retrievedTags, ['ACWR', 'Banister']);
    assert.equal(payload.fallbackTriggered, true);
    assert.equal(payload.schemaValidationFailed, true);
    assert.equal('reason' in payload, false);
    assert.equal('query' in payload, false);
    assert.equal('note' in payload, false);
    assert.equal('pageContent' in payload, false);
  });

  it('classifies orchestrator schema rejection vs missing key', () => {
    const schema = classifyOrchestratorFallback(
      'Agent output rejected (malformed_json) — used rule-based Orchestrator.',
    );
    assert.equal(schema.schemaValidationFailed, true);
    assert.equal(schema.schemaFailureReason, 'malformed_json');
    assert.equal(schema.fallbackReason, 'schema_or_business_rule');

    const key = classifyOrchestratorFallback(
      'ANTHROPIC_API_KEY missing — used rule-based Orchestrator.',
    );
    assert.equal(key.schemaValidationFailed, false);
    assert.equal(key.fallbackReason, 'missing_api_key');
  });
});

describe('LangSmith sink only receives redacted runs', () => {
  const posted: unknown[] = [];

  beforeEach(() => {
    posted.length = 0;
    process.env.LANGSMITH_TRACING = 'true';
    setLangSmithTestSink((run) => {
      posted.push(run);
    });
  });

  afterEach(() => {
    setLangSmithTestSink(null);
    delete process.env.LANGSMITH_TRACING;
  });

  it('is enabled only when LANGSMITH_TRACING=true', () => {
    assert.equal(isLangSmithDevTracingEnabled(), true);
    delete process.env.LANGSMITH_TRACING;
    assert.equal(isLangSmithDevTracingEnabled(), false);
  });

  it('orchestrator post omits identity and health even if mixed into the object', async () => {
    await traceOrchestratorToLangSmith({
      surface: 'orchestrator',
      privacy: 'redacted_no_phi',
      sportGroup: 'combat',
      toolCalls: [{ tool: 'getAthleteHistory', ok: true, latencyMs: 20 }],
      llmRoundtrips: 1,
      llmLatencyMs: 100,
      totalLatencyMs: 150,
      schemaValidationFailed: false,
      schemaFailureReason: null,
      fallbackTriggered: false,
      fallbackReason: null,
      source: 'agent',
      agreedWithRules: false,
      // @ts-expect-error intentional leak attempt
      athleteUid: '7o54AyrYprTUyTJzpKzXdz90lH33',
      athleteName: 'Alex Rivera',
      acwr: 1.4,
    });
    assert.equal(posted.length, 1);
    const blob = JSON.stringify(posted[0]);
    assert.equal(blob.includes('Alex Rivera'), false);
    assert.equal(blob.includes('7o54AyrYprTUyTJzpKzXdz90lH33'), false);
    assert.equal(blob.includes('"acwr"'), false);
    assert.equal(blob.includes('getAthleteHistory'), true);
    assert.equal(blob.includes('redacted_no_phi'), true);
    assert.equal(LANGSMITH_REDACT.length > 0, true);
  });

  it('knowledge post never includes retrieved page text or athlete reason', async () => {
    await traceKnowledgeToLangSmith({
      surface: 'knowledge_agent',
      privacy: 'redacted_no_phi',
      retrievedTags: ['session-RPE'],
      retrievedCount: 1,
      retrieveLatencyMs: 5,
      llmLatencyMs: 0,
      totalLatencyMs: 8,
      schemaValidationFailed: false,
      schemaFailureReason: null,
      fallbackTriggered: true,
      fallbackReason: 'missing_api_key',
      source: 'retrieved',
      // @ts-expect-error intentional leak attempt
      note: 'Alex ACWR 1.62',
      pageContent: 'corpus paragraph',
      reason: 'fatigue stuck high',
    });
    const blob = JSON.stringify(posted[0]);
    assert.equal(blob.includes('Alex'), false);
    assert.equal(blob.includes('1.62'), false);
    assert.equal(blob.includes('corpus paragraph'), false);
    assert.equal(blob.includes('fatigue stuck high'), false);
    assert.equal(blob.includes('session-RPE'), true);
    assert.equal(blob.includes('missing_api_key'), true);
  });
});
