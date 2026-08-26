/**
 * Schema + business-rule guardrails. These tests feed mocked LLM strings
 * (no Anthropic) and assert the same apply* helpers production uses
 * discard the output and take the rule-based path.
 */

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { applyExplainLlmResponse } from './explainabilityLlm';
import { applyGradedLlmResponse, fallbackGradedOptions } from './gradedRecommendations';
import { applyClassifyLlmResponse } from './sportClassifier';
import { applyOrchestratorLlmResponse } from './orchestratorAgent';
import { applyResearchLlmResponse } from './knowledgeAgent';
import { applyTriageLlmResponse, ruleBasedPainUrgency } from './painUrgency';
import { applyWeeklyLlmResponse } from './weeklyReport';
import {
  parseClassifyOutput,
  parseExplainOutput,
  parseGradedOutput,
  parseOrchestratorOutput,
  parseResearchOutput,
  parseTriageOutput,
  parseWeeklyOutput,
} from './llmGuardrails';
import { invokeOrchestratorTool } from './orchestratorTools';
import { buildRecommendation, recommendationOptions } from './recommendationEngine';
import { RiskAssessment } from './riskModel';

const mediumAssessment: RiskAssessment = {
  riskLevel: 'MEDIUM',
  confidence: 'medium',
  reason: 'ACWR 1.42 with worsening recovery.',
  acwr: 1.42,
  trainingLoad7d: 820,
  trainingLoad28dAvg: 610,
  recoveryTrend: 'worsening',
  performancePrediction: 'GOOD',
  performanceFrame: 'time/pace looking strong',
  performanceFrameAxis: 'time/pace',
};

const endurance = recommendationOptions('endurance');
const allowed = [endurance.HIGH, endurance.MEDIUM, endurance.LOW, endurance.LOW_DECLINING];
const ruleBasedHigh = buildRecommendation('HIGH', 'GOOD', 'endurance');

function validGradedJson(minimalAction: string): string {
  return JSON.stringify({
    options: [
      { tier: 'Conservative', action: endurance.HIGH, reason: 'Max cut.' },
      { tier: 'Moderate', action: endurance.MEDIUM, reason: 'Partial cut.' },
      { tier: 'Minimal change', action: minimalAction, reason: 'Smallest cut.' },
    ],
  });
}

describe('orchestrator guardrails', () => {
  it('accepts an exact allowed action when risk is HIGH', () => {
    const raw = JSON.stringify({
      action: endurance.HIGH,
      orchestratorNote: 'Risk wins; easy sessions only.',
      why: 'getRiskAssessment showed HIGH.',
    });
    const decided = applyOrchestratorLlmResponse(raw, {
      allowedActions: allowed,
      riskLevel: 'HIGH',
      ruleBased: ruleBasedHigh,
      trace: [],
    });
    assert.equal(decided.source, 'agent');
    assert.equal(decided.action, endurance.HIGH);
  });

  it('falls back on malformed JSON', () => {
    const decided = applyOrchestratorLlmResponse('{ "action": ', {
      allowedActions: allowed,
      riskLevel: 'HIGH',
      ruleBased: ruleBasedHigh,
      trace: [],
    });
    assert.equal(decided.source, 'rules_fallback');
    assert.equal(decided.action, ruleBasedHigh.action);
    assert.match(decided.trace[decided.trace.length - 1]?.why ?? '', /malformed_json/);
  });

  it('falls back when action is not on the sport allowed list', () => {
    const decided = applyOrchestratorLlmResponse(
      JSON.stringify({
        action: 'Go race a 5K at full effort tomorrow.',
        orchestratorNote: 'Performance looks good.',
        why: 'invented',
      }),
      {
        allowedActions: allowed,
        riskLevel: 'LOW',
        ruleBased: buildRecommendation('LOW', 'GOOD', 'endurance'),
        trace: [],
      },
    );
    assert.equal(decided.source, 'rules_fallback');
    assert.equal(decided.action, endurance.LOW);
    assert.match(decided.trace[decided.trace.length - 1]?.why ?? '', /action_not_in_allowed_list/);
  });

  it('discards Continue training as planned when risk is HIGH (does not patch)', () => {
    const decided = applyOrchestratorLlmResponse(
      JSON.stringify({
        action: endurance.LOW,
        orchestratorNote: 'Fitness is high so keep racing.',
        why: 'performance over risk',
      }),
      {
        allowedActions: allowed,
        riskLevel: 'HIGH',
        ruleBased: ruleBasedHigh,
        trace: [],
      },
    );
    assert.equal(decided.source, 'rules_fallback');
    assert.equal(decided.action, ruleBasedHigh.action);
    assert.notEqual(decided.action, endurance.LOW);
    assert.match(decided.trace[decided.trace.length - 1]?.why ?? '', /full_training_when_elevated_risk/);
  });
});

describe('graded guardrails', () => {
  it('accepts three unique tiers when none are full training at MEDIUM', () => {
    const result = applyGradedLlmResponse(validGradedJson(endurance.MEDIUM), {
      assessment: mediumAssessment,
      sportGroup: 'endurance',
      primaryAction: endurance.MEDIUM,
    });
    assert.equal(result.source, 'llm');
    assert.equal(result.options.length, 3);
  });

  it('falls back when JSON is missing fields', () => {
    const result = applyGradedLlmResponse('{"options":[{"tier":"Conservative"}]}', {
      assessment: mediumAssessment,
      sportGroup: 'endurance',
      primaryAction: endurance.MEDIUM,
    });
    assert.equal(result.source, 'rules');
    assert.deepEqual(
      result.options,
      fallbackGradedOptions(mediumAssessment, 'endurance', endurance.MEDIUM),
    );
  });

  it('discards the whole LLM set if Minimal change is full training at MEDIUM', () => {
    const result = applyGradedLlmResponse(validGradedJson(endurance.LOW), {
      assessment: mediumAssessment,
      sportGroup: 'endurance',
      primaryAction: endurance.MEDIUM,
    });
    assert.equal(result.source, 'rules');
    assert.ok(result.options.every((o) => !/continue training as planned/i.test(o.action)));
  });
});

describe('explain guardrails', () => {
  const validExplain = JSON.stringify({
    riskLevelReasoningLLM: 'Locked MEDIUM matches ACWR 1.42 and worsening recovery over five days.',
    riskLevelPatternFlag: null,
    performanceReasoningLLM: 'Performance is still GOOD on the time/pace frame from the same series.',
  });

  it('accepts prose that keeps the locked band', () => {
    const result = applyExplainLlmResponse(validExplain, mediumAssessment);
    assert.equal(result.source, 'llm');
  });

  it('falls back when the model emits a different riskLevel field', () => {
    const raw = JSON.stringify({
      riskLevel: 'LOW',
      riskLevelReasoningLLM: 'This is actually fine.',
      riskLevelPatternFlag: null,
      performanceReasoningLLM: 'Keep racing.',
    });
    const parsed = parseExplainOutput(raw, { lockedRiskLevel: 'MEDIUM' });
    assert.equal(parsed.ok, false);
    if (!parsed.ok) assert.equal(parsed.reason, 'business:attempted_to_change_locked_riskLevel');
    const result = applyExplainLlmResponse(raw, mediumAssessment);
    assert.equal(result.source, 'rules');
    assert.equal(result.riskLevelReasoningLLM, mediumAssessment.reason);
  });

  it('falls back when prose upgrades the locked risk', () => {
    const raw = JSON.stringify({
      riskLevelReasoningLLM: 'Numbers look mild but this should be HIGH given the load.',
      riskLevelPatternFlag: null,
      performanceReasoningLLM: 'Performance still GOOD.',
    });
    const result = applyExplainLlmResponse(raw, mediumAssessment);
    assert.equal(result.source, 'rules');
  });
});

describe('research / triage / classify / weekly shape checks', () => {
  it('research: malformed JSON falls back', () => {
    const fallback = {
      note: 'retrieved note',
      citations: [{ tag: 'ACWR', text: 'chunk', source: 'file.md' }],
      source: 'retrieved' as const,
    };
    const result = applyResearchLlmResponse('not json', fallback);
    assert.equal(result.source, 'retrieved');
    assert.equal(result.note, fallback.note);
  });

  it('research: missing citation fields falls back', () => {
    const parsed = parseResearchOutput('{"note":"ok","citations":[{"tag":"x"}]}');
    assert.equal(parsed.ok, false);
  });

  it('triage: invalid urgency uses rules', () => {
    const note = 'sharp stabbing pain after a pop';
    const areas = [{ location: 'knee', severity: 5 }];
    const rules = ruleBasedPainUrgency(note, areas);
    const result = applyTriageLlmResponse(
      '{"urgency":"CRITICAL","reason":"sounds bad"}',
      note,
      areas,
    );
    assert.equal(result.source, 'rules');
    assert.equal(result.urgency, rules.urgency);
  });

  it('triage: happy path keeps llm source', () => {
    const result = applyTriageLlmResponse(
      '{"urgency":"HIGH","reason":"pop plus high severity"}',
      'sore',
      [{ location: 'knee', severity: 2 }],
    );
    assert.equal(result.source, 'llm');
    assert.equal(result.urgency, 'HIGH');
  });

  it('classify: invented group uses rules fallback', () => {
    const result = applyClassifyLlmResponse(
      '{"sportGroup":"quidditch","confidence":"high","reason":"magic"}',
      'quidditch',
    );
    assert.equal(result.source, 'rules');
    assert.equal(result.sportGroup, 'other');
  });

  it('classify: valid endurance is llm', () => {
    const result = applyClassifyLlmResponse(
      '{"sportGroup":"endurance","confidence":"high","reason":"running"}',
      'trail running',
    );
    assert.equal(result.source, 'llm');
    assert.equal(result.sportGroup, 'endurance');
  });

  it('weekly: empty narrative uses rules', () => {
    const result = applyWeeklyLlmResponse('{"narrative":"   "}', 'rule narrative');
    assert.equal(result.source, 'rules');
    assert.equal(result.narrative, 'rule narrative');
  });

  it('weekly: valid narrative is llm', () => {
    const result = applyWeeklyLlmResponse(
      '{"narrative":"Six sessions, sleep held, fatigue eased late week."}',
      'rule narrative',
    );
    assert.equal(result.source, 'llm');
  });
});

describe('parser rejects wrong types', () => {
  it('orchestrator action must be a string', () => {
    const parsed = parseOrchestratorOutput(
      '{"action":1,"orchestratorNote":"x"}',
      { allowedActions: allowed, riskLevel: 'LOW' },
    );
    assert.equal(parsed.ok, false);
  });

  it('graded requires exactly three unique tiers', () => {
    const parsed = parseGradedOutput(
      JSON.stringify({
        options: [
          { tier: 'Conservative', action: 'a', reason: 'r' },
          { tier: 'Conservative', action: 'b', reason: 'r' },
          { tier: 'Moderate', action: 'c', reason: 'r' },
        ],
      }),
      { riskLevel: 'LOW' },
    );
    assert.equal(parsed.ok, false);
  });

  it('classify confidence must be high or low', () => {
    const parsed = parseClassifyOutput(
      '{"sportGroup":"endurance","confidence":"maybe"}',
    );
    assert.equal(parsed.ok, false);
  });

  it('triage urgency is an enum', () => {
    const parsed = parseTriageOutput('{"urgency":"medium-high","reason":"x"}');
    assert.equal(parsed.ok, false);
  });

  it('weekly narrative must be a string', () => {
    const parsed = parseWeeklyOutput('{"narrative":["two","lines"]}');
    assert.equal(parsed.ok, false);
  });
});

describe('orchestrator tools are bound to the session athlete', () => {
  it('never loads Firestore for a model-supplied other athleteId', async () => {
    const seen: string[] = [];
    const load = async (athleteUid: string) => {
      seen.push(athleteUid);
      return [];
    };
    const out = await invokeOrchestratorTool(
      'getAthleteHistory',
      { athleteId: 'other-athlete-uid', days: 14 },
      load,
      'session-athlete-uid',
    );
    assert.deepEqual(seen, ['session-athlete-uid']);
    const parsed = JSON.parse(out) as { checkInCount: number };
    assert.equal(parsed.checkInCount, 0);
  });

  it('refuses to run without a bound athlete id', async () => {
    const seen: string[] = [];
    const load = async (athleteUid: string) => {
      seen.push(athleteUid);
      return [];
    };
    const out = await invokeOrchestratorTool('getRiskAssessment', { athleteId: 'anyone' }, load);
    assert.deepEqual(seen, []);
    assert.equal(JSON.parse(out).error, 'missing_bound_athleteId');
  });
});
