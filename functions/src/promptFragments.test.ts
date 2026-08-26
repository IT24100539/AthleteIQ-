/**
 * Locks shared prompt clauses into every system prompt that needs them,
 * and locks ChatPromptTemplate JSON examples to doubled-brace escaping.
 */
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { ChatPromptTemplate } from '@langchain/core/prompts';
import { SYSTEM_PROMPT } from './aiChat';
import { EXPLAIN_PROMPT } from './explainabilityLlm';
import { GRADED_PROMPT } from './gradedRecommendations';
import { RESEARCH_PROMPT } from './knowledgeAgent';
import { ORCHESTRATOR_SYSTEM_PROMPT } from './orchestratorAgent';
import { TRIAGE_PROMPT } from './painUrgency';
import {
  CORPUS_GROUNDING_INSTRUCTION,
  GROUNDING_INSTRUCTION,
  jsonExampleForChatPrompt,
  MEDICAL_DISCLAIMER,
  MEDICAL_ESCALATE,
  MISSING_METRIC_DISCLOSE,
  MISSING_METRIC_OMIT,
  RISK_OVERRIDES_PERFORMANCE_CLAUSE,
  TOOL_GROUNDING_INSTRUCTION,
} from './promptFragments';
import { CLASSIFY_PROMPT } from './sportClassifier';
import { NARRATIVE_PROMPT } from './weeklyReport';

function systemInputVars(system: string): string[] {
  const prompt = ChatPromptTemplate.fromMessages([['system', system]]);
  return [...prompt.inputVariables].sort();
}

describe('jsonExampleForChatPrompt', () => {
  it('doubles braces so ChatPromptTemplate sees no extra variables', () => {
    const raw = '{"narrative":"..."}';
    const escaped = jsonExampleForChatPrompt(raw);
    assert.equal(escaped, '{{"narrative":"..."}}');
    assert.deepEqual(systemInputVars(`Return ${escaped}`), []);
  });
});

describe('shared clauses appear in the prompts that need them', () => {
  it('Ask AthleteIQ uses grounding, disclose-missing, and medical+escalate', () => {
    assert.ok(SYSTEM_PROMPT.includes(GROUNDING_INSTRUCTION));
    assert.ok(SYSTEM_PROMPT.includes(MISSING_METRIC_DISCLOSE));
    assert.ok(SYSTEM_PROMPT.includes(MEDICAL_DISCLAIMER));
    assert.ok(SYSTEM_PROMPT.includes(MEDICAL_ESCALATE));
  });

  it('Orchestrator uses risk-overrides, medical, and tool grounding', () => {
    assert.ok(ORCHESTRATOR_SYSTEM_PROMPT.includes(RISK_OVERRIDES_PERFORMANCE_CLAUSE));
    assert.ok(ORCHESTRATOR_SYSTEM_PROMPT.includes(MEDICAL_DISCLAIMER));
    assert.ok(ORCHESTRATOR_SYSTEM_PROMPT.includes(TOOL_GROUNDING_INSTRUCTION));
    assert.ok(ORCHESTRATOR_SYSTEM_PROMPT.includes(GROUNDING_INSTRUCTION));
  });

  it('Graded uses grounding, risk-overrides (all tiers), and medical', () => {
    assert.ok(GRADED_PROMPT.includes(GROUNDING_INSTRUCTION));
    assert.ok(GRADED_PROMPT.includes(RISK_OVERRIDES_PERFORMANCE_CLAUSE));
    assert.ok(GRADED_PROMPT.includes(MEDICAL_DISCLAIMER));
    assert.ok(GRADED_PROMPT.includes('Conservative, Moderate, or Minimal change'));
  });

  it('Explain uses grounding + disclose-missing', () => {
    assert.ok(EXPLAIN_PROMPT.includes(GROUNDING_INSTRUCTION));
    assert.ok(EXPLAIN_PROMPT.includes(MISSING_METRIC_DISCLOSE));
  });

  it('Knowledge Agent uses corpus grounding (includes number grounding)', () => {
    assert.ok(RESEARCH_PROMPT.includes(CORPUS_GROUNDING_INSTRUCTION));
    assert.ok(RESEARCH_PROMPT.includes(GROUNDING_INSTRUCTION));
  });

  it('Triage uses medical disclaimer and number grounding', () => {
    assert.ok(TRIAGE_PROMPT.includes(MEDICAL_DISCLAIMER));
    assert.ok(TRIAGE_PROMPT.includes(GROUNDING_INSTRUCTION));
  });

  it('Weekly report uses grounding, omit-missing, and medical', () => {
    assert.ok(NARRATIVE_PROMPT.includes(GROUNDING_INSTRUCTION));
    assert.ok(NARRATIVE_PROMPT.includes(MISSING_METRIC_OMIT));
    assert.ok(NARRATIVE_PROMPT.includes(MEDICAL_DISCLAIMER));
  });
});

describe('ChatPromptTemplate prompts do not leak JSON keys as variables', () => {
  it('Ask AthleteIQ system prompt has no template variables', () => {
    assert.deepEqual(systemInputVars(SYSTEM_PROMPT), []);
  });

  it('GRADED_PROMPT has no template variables', () => {
    assert.deepEqual(systemInputVars(GRADED_PROMPT), []);
  });

  it('EXPLAIN_PROMPT has no template variables', () => {
    assert.deepEqual(systemInputVars(EXPLAIN_PROMPT), []);
  });

  it('TRIAGE_PROMPT has no template variables', () => {
    assert.deepEqual(systemInputVars(TRIAGE_PROMPT), []);
  });

  it('CLASSIFY_PROMPT has no template variables (was single-brace JSON)', () => {
    assert.deepEqual(systemInputVars(CLASSIFY_PROMPT), []);
  });

  it('NARRATIVE_PROMPT has no template variables (was single-brace JSON)', () => {
    assert.deepEqual(systemInputVars(NARRATIVE_PROMPT), []);
  });
});
