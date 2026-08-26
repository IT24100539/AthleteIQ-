import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  buildAthleteRiskView,
  buildCheckInCoachView,
  isRecommendationReleased,
} from './privacyViews';
import { OPEN_PRIVACY } from './privacySettings';

describe('buildAthleteRiskView', () => {
  const latest = {
    riskLevel: 'HIGH',
    confidence: 'Medium',
    reason: 'Load climbing',
    acwr: 1.6,
    trainingLoad7d: 400,
    trainingLoad28dAvg: 250,
    recoveryTrend: 'worsening',
    performancePrediction: 'DECLINING',
    recommendation: 'Cut volume 20%',
    recommendationStatus: 'pending',
    gradedOptions: [{ tier: 'conservative', action: 'Rest', reason: 'Spike' }],
    researchNote: 'Gabbett',
    orchestratorConflict: { present: true },
    calculatedAt: '2026-08-15T12:00:00.000Z',
  };

  it('omits Orchestrator, graded options, and LLM prose while pending', () => {
    const view = buildAthleteRiskView({
      ...latest,
      recommendationStatus: 'pending',
      orchestratorSource: 'llm',
      gradedOptionsSource: 'llm',
      riskLevelReasoningLLM: 'LLM risk',
      performanceReasoningLLM: 'LLM performance',
      ruleBasedRecommendation: 'Rule rec',
    });
    assert.equal(view.recommendation, undefined);
    assert.equal(view.gradedOptions, undefined);
    assert.equal(view.researchNote, undefined);
    assert.equal(view.orchestratorConflict, undefined);
    assert.equal(view.orchestratorSource, undefined);
    assert.equal(view.riskLevelReasoningLLM, undefined);
    assert.equal(view.performanceReasoningLLM, undefined);
    assert.equal(view.ruleBasedRecommendation, undefined);
    assert.equal(view.riskLevel, 'HIGH');
    assert.equal(view.acwr, 1.6);
    assert.equal(view.recommendationStatus, 'pending');
    assert.equal(view.reason, undefined);
  });

  it('copies the released plan after approval', () => {
    const view = buildAthleteRiskView({
      ...latest,
      recommendationStatus: 'approved',
    });
    assert.equal(view.recommendation, 'Cut volume 20%');
    assert.equal(view.reason, 'Load climbing');
    assert.ok(Array.isArray(view.gradedOptions));
    assert.equal(view.orchestratorConflict, undefined);
  });
});

describe('buildCheckInCoachView', () => {
  const checkIn = {
    date: '2026-08-14',
    sessionDurationMinutes: 45,
    rpe: 6,
    fatigueScore: 4,
    sleepHours: 7.5,
    hrv: 68,
    soreness: 'Left knee',
    source: 'manual',
  };

  it('copies every shared field', () => {
    const view = buildCheckInCoachView(checkIn, OPEN_PRIVACY);
    assert.equal(view.fatigueScore, 4);
    assert.equal(view.hrv, 68);
    assert.equal(view.rpe, 6);
    assert.equal(view.soreness, 'Left knee');
  });

  it('omits fatigue when dailyFatigueCheckIn is off', () => {
    const view = buildCheckInCoachView(checkIn, {
      ...OPEN_PRIVACY,
      dailyFatigueCheckIn: false,
    });
    assert.equal(view.fatigueScore, undefined);
    assert.equal(view.rpe, 6);
  });
});

describe('isRecommendationReleased', () => {
  it('treats approved and modified as released', () => {
    assert.equal(isRecommendationReleased('pending'), false);
    assert.equal(isRecommendationReleased('approved'), true);
    assert.equal(isRecommendationReleased('modified'), true);
  });
});
