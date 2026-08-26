import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { ChatPromptTemplate } from '@langchain/core/prompts';
import {
  CORPUS_GROUNDING_INSTRUCTION,
  GROUNDING_INSTRUCTION,
  MEDICAL_DISCLAIMER,
  RISK_OVERRIDES_PERFORMANCE_CLAUSE,
  TOOL_GROUNDING_INSTRUCTION,
} from '../promptFragments';
import { parseJudgeJsonForTest, scoreFromItems, JUDGE_SYSTEM_FOR_TEST } from './judge';
import {
  FIRST_PASS_KINDS,
  formatRubricForJudge,
  PROMPT_KINDS,
  RUBRICS,
  rubricFor,
} from './rubric';

describe('LLM evaluation rubrics', () => {
  it('covers all eight prompt types', () => {
    assert.deepEqual([...PROMPT_KINDS].sort(), [
      'askAthleteIQ',
      'classify',
      'explain',
      'graded',
      'orchestrator',
      'research',
      'triage',
      'weekly',
    ]);
    for (const kind of PROMPT_KINDS) {
      assert.equal(RUBRICS[kind].kind, kind);
      assert.ok(RUBRICS[kind].items.length >= 2);
    }
  });

  it('quotes live safety/grounding clauses', () => {
    assert.ok(formatRubricForJudge('askAthleteIQ').includes(GROUNDING_INSTRUCTION));
    assert.ok(formatRubricForJudge('askAthleteIQ').includes(MEDICAL_DISCLAIMER));
    assert.ok(formatRubricForJudge('orchestrator').includes(RISK_OVERRIDES_PERFORMANCE_CLAUSE));
    assert.ok(formatRubricForJudge('orchestrator').includes(TOOL_GROUNDING_INSTRUCTION));
    assert.ok(formatRubricForJudge('graded').includes(RISK_OVERRIDES_PERFORMANCE_CLAUSE));
    assert.ok(formatRubricForJudge('graded').includes(GROUNDING_INSTRUCTION));
    assert.ok(formatRubricForJudge('explain').includes(GROUNDING_INSTRUCTION));
    assert.ok(formatRubricForJudge('research').includes(CORPUS_GROUNDING_INSTRUCTION));
    assert.ok(formatRubricForJudge('triage').includes(MEDICAL_DISCLAIMER));
    assert.ok(formatRubricForJudge('triage').includes(GROUNDING_INSTRUCTION));
    assert.ok(formatRubricForJudge('weekly').includes(GROUNDING_INSTRUCTION));
    assert.ok(formatRubricForJudge('weekly').includes(MEDICAL_DISCLAIMER));
  });

  it('first-pass kinds are the five stored generators', () => {
    assert.deepEqual(FIRST_PASS_KINDS, [
      'askAthleteIQ',
      'orchestrator',
      'graded',
      'explain',
      'research',
    ]);
  });
});

describe('scoreFromItems', () => {
  it('fails overall when a required item fails', () => {
    const rubric = rubricFor('graded');
    const items = rubric.items.map((spec) => ({
      id: spec.id,
      pass: spec.id !== 'risk_overrides_all_tiers',
      evidence: '',
      reason: '',
    }));
    const scored = scoreFromItems(items, rubric);
    assert.equal(scored.overallPass, false);
    assert.ok(scored.overallScore < 5);
  });

  it('passes overall when every required item passes', () => {
    const rubric = rubricFor('classify');
    const items = rubric.items.map((spec) => ({
      id: spec.id,
      pass: true,
      evidence: 'ok',
      reason: 'ok',
    }));
    const scored = scoreFromItems(items, rubric);
    assert.equal(scored.overallPass, true);
    assert.equal(scored.overallScore, 5);
  });
});

describe('parseJudgeJsonForTest', () => {
  it('fills omitted rubric items as fails', () => {
    const rubric = rubricFor('classify');
    const parsed = parseJudgeJsonForTest(
      '{"items":[{"id":"valid_group","pass":true,"evidence":"endurance","reason":"ok"}],"overallScore":5,"verbosityBiasRisk":"low","summary":"fine"}',
      rubric,
    );
    assert.ok(parsed);
    assert.equal(parsed.items.length, 2);
    assert.equal(parsed.items.find((i) => i.id === 'low_when_unsure')?.pass, false);
  });
});

describe('judge system prompt brace escaping', () => {
  it('has no leftover ChatPromptTemplate variables', () => {
    const prompt = ChatPromptTemplate.fromMessages([['system', JUDGE_SYSTEM_FOR_TEST]]);
    assert.deepEqual([...prompt.inputVariables].sort(), []);
  });
});
