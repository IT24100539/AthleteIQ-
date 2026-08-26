/**
 * Non-negotiables — dedicated permanent regression suite.
 *
 * If any of these fail after a future change, a critical product rule broke.
 * Names are the rule. Do not "fix" a failure by loosening the assertion.
 */

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { athleteAccessDecision, canAccessAthlete } from './athleteAccess';
import { buildChatContext } from './aiChat';
import { calculateACWR, DailyEntry, shiftDateKey } from './calculations';
import {
  isMissedCheckIn,
  isRiskSpike,
  planNightlyAlerts,
  syncIssueFromDevices,
} from './nightlyAlerts';
import {
  buildAthleteRiskView,
  isRecommendationReleased,
} from './privacyViews';
import { statusForNewRiskWrite } from './riskPipeline';
import { shouldNotifyRecommendationRelease } from './recommendationNotify';
import { assessRisk } from './riskModel';

const AS_OF = '2026-08-21';
const ATHLETE_A = 'athlete-a';
const ATHLETE_B = 'athlete-b';
const COACH_C = 'coach-c';
const COACH_D = 'coach-d';

function entry(
  date: string,
  trainingLoad: number,
  extras: Partial<DailyEntry> = {},
): DailyEntry {
  return {
    date,
    trainingLoad,
    sleepHours: 8,
    restingHeartRate: 50,
    hrv: 60,
    fatigueScore: 2,
    ...extras,
  };
}

/**
 * 28 calendar days, recent-first. Last 7 days use `acuteLoad`; the prior
 * 21 days use `chronicDayLoad`. Chosen so ACWR is exact:
 *   ACWR = 4 * acuteLoad / (acuteLoad + 3 * chronicDayLoad)
 */
function loadSeries(opts: {
  acuteLoad: number;
  chronicDayLoad: number;
  recentHrv?: number;
  priorHrv?: number;
  recentFatigue?: number;
  olderFatigue?: number;
}): DailyEntry[] {
  const recentHrv = opts.recentHrv ?? 60;
  const priorHrv = opts.priorHrv ?? 60;
  const recentFatigue = opts.recentFatigue ?? 2;
  const olderFatigue = opts.olderFatigue ?? 2;
  const out: DailyEntry[] = [];
  for (let i = 0; i < 28; i++) {
    const date = shiftDateKey(AS_OF, -i);
    const load = i < 7 ? opts.acuteLoad : opts.chronicDayLoad;
    const hrv = i < 7 ? recentHrv : priorHrv;
    const fatigueScore = i < 4 ? recentFatigue : olderFatigue;
    out.push(entry(date, load, { hrv, fatigueScore }));
  }
  return out;
}

describe('NON-NEGOTIABLE: athlete/coach access boundaries', () => {
  it('athlete cannot read another athlete (application gate denies)', () => {
    assert.equal(
      athleteAccessDecision({
        callerUid: ATHLETE_B,
        athleteUid: ATHLETE_A,
        coachUid: COACH_C,
      }),
      'denied',
    );
    assert.equal(
      canAccessAthlete({
        callerUid: ATHLETE_B,
        athleteUid: ATHLETE_A,
        coachUid: COACH_C,
      }),
      false,
    );
  });

  it('coach cannot read an athlete not on their roster (application gate denies)', () => {
    assert.equal(
      athleteAccessDecision({
        callerUid: COACH_D,
        athleteUid: ATHLETE_A,
        coachUid: COACH_C,
      }),
      'denied',
    );
    assert.equal(
      canAccessAthlete({
        callerUid: COACH_D,
        athleteUid: ATHLETE_A,
        coachUid: COACH_C,
      }),
      false,
    );
  });

  it('athlete can access their own data; assigned coach can access roster athlete', () => {
    assert.equal(
      athleteAccessDecision({
        callerUid: ATHLETE_A,
        athleteUid: ATHLETE_A,
        coachUid: COACH_C,
      }),
      'self',
    );
    assert.equal(
      athleteAccessDecision({
        callerUid: COACH_C,
        athleteUid: ATHLETE_A,
        coachUid: COACH_C,
      }),
      'coach',
    );
  });

  it('unassigned athlete (no coachUid) is not readable by any coach', () => {
    assert.equal(
      athleteAccessDecision({
        callerUid: COACH_C,
        athleteUid: ATHLETE_A,
        coachUid: null,
      }),
      'denied',
    );
  });

  it('empty caller or athlete id is denied', () => {
    assert.equal(
      athleteAccessDecision({ callerUid: '', athleteUid: ATHLETE_A, coachUid: COACH_C }),
      'denied',
    );
    assert.equal(
      athleteAccessDecision({ callerUid: ATHLETE_A, athleteUid: '', coachUid: COACH_C }),
      'denied',
    );
  });
});

describe('NON-NEGOTIABLE: ACWR risk thresholds (1.5 / 1.3 / 0.8)', () => {
  it('ACWR exactly 1.5 is MEDIUM — HIGH requires strictly above 1.5 plus worsening recovery and persistent fatigue', () => {
    // 4*180 / (180 + 3*100) = 720/480 = 1.5
    const entries = loadSeries({
      acuteLoad: 180,
      chronicDayLoad: 100,
      recentHrv: 50,
      priorHrv: 70,
      recentFatigue: 4,
      olderFatigue: 2,
    });
    const { acwr } = calculateACWR(entries, AS_OF);
    assert.equal(acwr, 1.5);
    const assessment = assessRisk(entries, 'endurance', AS_OF);
    assert.equal(assessment.acwr, 1.5);
    assert.equal(assessment.riskLevel, 'MEDIUM');
    assert.equal(assessment.recoveryTrend, 'worsening');
    assert.equal(assessment.reason.includes('fatigue'), true);
  });

  it('ACWR just above 1.5 with worsening recovery and persistent fatigue is HIGH', () => {
    const entries = loadSeries({
      acuteLoad: 181,
      chronicDayLoad: 100,
      recentHrv: 50,
      priorHrv: 70,
      recentFatigue: 4,
      olderFatigue: 2,
    });
    const { acwr } = calculateACWR(entries, AS_OF);
    assert.ok(acwr > 1.5);
    assert.equal(assessRisk(entries, 'endurance', AS_OF).riskLevel, 'HIGH');
  });

  it('ACWR exactly 1.3 with stable recovery is LOW (inclusive upper bound of the sweet spot)', () => {
    // 4*390 / (390 + 3*270) = 1560/1200 = 1.3
    const entries = loadSeries({
      acuteLoad: 390,
      chronicDayLoad: 270,
    });
    const { acwr } = calculateACWR(entries, AS_OF);
    assert.equal(acwr, 1.3);
    assert.equal(assessRisk(entries, 'endurance', AS_OF).riskLevel, 'LOW');
  });

  it('ACWR just above 1.3 is MEDIUM (climbing), even if recovery is stable', () => {
    const entries = loadSeries({
      acuteLoad: 391,
      chronicDayLoad: 270,
    });
    const { acwr } = calculateACWR(entries, AS_OF);
    assert.ok(acwr > 1.3);
    assert.ok(acwr < 1.5);
    assert.equal(assessRisk(entries, 'endurance', AS_OF).riskLevel, 'MEDIUM');
  });

  it('ACWR exactly 0.8 with stable recovery is LOW (inclusive lower bound of the sweet spot)', () => {
    // 4*75 / (75 + 3*100) = 300/375 = 0.8
    const entries = loadSeries({
      acuteLoad: 75,
      chronicDayLoad: 100,
    });
    const { acwr } = calculateACWR(entries, AS_OF);
    assert.equal(acwr, 0.8);
    assert.equal(assessRisk(entries, 'endurance', AS_OF).riskLevel, 'LOW');
  });

  it('ACWR just below 0.8 is MEDIUM (below the stable band)', () => {
    const entries = loadSeries({
      acuteLoad: 74,
      chronicDayLoad: 100,
    });
    const { acwr } = calculateACWR(entries, AS_OF);
    assert.ok(acwr < 0.8);
    assert.equal(assessRisk(entries, 'endurance', AS_OF).riskLevel, 'MEDIUM');
  });
});

describe('NON-NEGOTIABLE: alert creation and recipient scoping', () => {
  const now = new Date('2026-08-21T12:00:00.000Z');
  const threeDaysAgo = new Date('2026-08-18T12:00:00.000Z');
  const today = new Date('2026-08-21T08:00:00.000Z');
  const createdLongAgo = new Date('2026-01-01T00:00:00.000Z');

  it('risk spike (LOW → HIGH) creates athlete alert AND assigned-coach alert only', () => {
    const plan = planNightlyAlerts({
      athleteUid: ATHLETE_A,
      athleteName: 'Athlete A',
      coachUid: COACH_C,
      previousRiskLevel: 'LOW',
      newRiskLevel: 'HIGH',
      lastCheckInAt: today,
      athleteCreatedAt: createdLongAgo,
      syncIssue: null,
      now,
    });
    assert.equal(plan.riskSpikes, 1);
    assert.equal(plan.athleteAlerts.length, 1);
    assert.equal(plan.athleteAlerts[0].type, 'risk_spike');
    assert.equal(plan.athleteAlerts[0].athleteUid, ATHLETE_A);
    assert.equal(plan.coachAlerts.length, 1);
    assert.equal(plan.coachAlerts[0].type, 'risk_spike');
    assert.equal(plan.coachAlerts[0].coachUid, COACH_C);
    assert.equal(plan.coachAlerts[0].athleteUid, ATHLETE_A);
    assert.ok(!plan.coachAlerts.some((a) => a.coachUid === COACH_D));
    assert.ok(!plan.athleteAlerts.some((a) => a.athleteUid === ATHLETE_B));
  });

  it('risk spike with no assigned coach writes athlete alert only', () => {
    const plan = planNightlyAlerts({
      athleteUid: ATHLETE_A,
      athleteName: 'Athlete A',
      coachUid: null,
      previousRiskLevel: 'MEDIUM',
      newRiskLevel: 'HIGH',
      lastCheckInAt: today,
      athleteCreatedAt: createdLongAgo,
      syncIssue: null,
      now,
    });
    assert.equal(plan.riskSpikes, 1);
    assert.equal(plan.athleteAlerts.length, 1);
    assert.equal(plan.coachAlerts.length, 0);
  });

  it('same risk tier is not a spike and creates no risk_spike alert', () => {
    assert.equal(isRiskSpike('HIGH', 'HIGH'), false);
    assert.equal(isRiskSpike('MEDIUM', 'LOW'), false);
    const plan = planNightlyAlerts({
      athleteUid: ATHLETE_A,
      athleteName: 'Athlete A',
      coachUid: COACH_C,
      previousRiskLevel: 'HIGH',
      newRiskLevel: 'HIGH',
      lastCheckInAt: today,
      athleteCreatedAt: createdLongAgo,
      syncIssue: null,
      now,
    });
    assert.equal(plan.riskSpikes, 0);
    assert.ok(!plan.athleteAlerts.some((a) => a.type === 'risk_spike'));
  });

  it('missed check-in (2+ days) creates athlete + assigned-coach alerts', () => {
    assert.equal(
      isMissedCheckIn({
        lastCheckInAt: threeDaysAgo,
        now,
        athleteCreatedAt: createdLongAgo,
      }),
      true,
    );
    const plan = planNightlyAlerts({
      athleteUid: ATHLETE_A,
      athleteName: 'Athlete A',
      coachUid: COACH_C,
      previousRiskLevel: 'LOW',
      newRiskLevel: 'LOW',
      lastCheckInAt: threeDaysAgo,
      athleteCreatedAt: createdLongAgo,
      syncIssue: null,
      now,
    });
    assert.equal(plan.missedCheckIns, 1);
    const athlete = plan.athleteAlerts.find((a) => a.type === 'missed_checkin');
    const coach = plan.coachAlerts.find((a) => a.type === 'missed_checkin');
    assert.ok(athlete);
    assert.equal(athlete?.athleteUid, ATHLETE_A);
    assert.ok(coach);
    assert.equal(coach?.coachUid, COACH_C);
    assert.equal(coach?.athleteUid, ATHLETE_A);
  });

  it('fresh athlete (< 2 days old) does not get a missed-check-in alert', () => {
    const createdYesterday = new Date('2026-08-20T12:00:00.000Z');
    assert.equal(
      isMissedCheckIn({
        lastCheckInAt: null,
        now,
        athleteCreatedAt: createdYesterday,
      }),
      false,
    );
  });

  it('sync failure creates athlete + assigned-coach alerts; healthy wearable does not', () => {
    const issue = syncIssueFromDevices(
      [{ id: 'garmin', connected: true, lastSyncError: 'token expired' }],
      now,
    );
    assert.equal(issue, 'token expired');
    assert.equal(
      syncIssueFromDevices(
        [{ id: 'garmin', connected: true, lastSync: now.toISOString() }],
        now,
      ),
      null,
    );

    const plan = planNightlyAlerts({
      athleteUid: ATHLETE_A,
      athleteName: 'Athlete A',
      coachUid: COACH_C,
      previousRiskLevel: 'LOW',
      newRiskLevel: 'LOW',
      lastCheckInAt: today,
      athleteCreatedAt: createdLongAgo,
      syncIssue: issue,
      now,
    });
    assert.equal(plan.syncFailures, 1);
    assert.ok(plan.athleteAlerts.some((a) => a.type === 'sync_failure' && a.athleteUid === ATHLETE_A));
    assert.ok(plan.coachAlerts.some((a) => a.type === 'sync_failure' && a.coachUid === COACH_C));
  });
});

describe('NON-NEGOTIABLE: coach approval gate — recommendation cannot reach the athlete unless approved/modified', () => {
  const pendingLatest = {
    riskLevel: 'HIGH',
    confidence: 'Medium',
    reason: 'Load climbing',
    acwr: 1.6,
    trainingLoad7d: 400,
    trainingLoad28dAvg: 250,
    recoveryTrend: 'worsening',
    performancePrediction: 'DECLINING',
    recommendation: 'Cut volume 20% — secret pending plan',
    recommendationStatus: 'pending',
    gradedOptions: [{ tier: 'Conservative', action: 'Full rest', reason: 'Spike' }],
    calculatedAt: '2026-08-21T12:00:00.000Z',
  };

  it('pipeline new writes are always pending — never auto-approved', () => {
    assert.equal(statusForNewRiskWrite(), 'pending');
    assert.notEqual(statusForNewRiskWrite(), 'approved');
    assert.notEqual(statusForNewRiskWrite(), 'modified');
  });

  it('pending / rejected / unknown status is not released', () => {
    assert.equal(isRecommendationReleased('pending'), false);
    assert.equal(isRecommendationReleased('rejected'), false);
    assert.equal(isRecommendationReleased('orchestrator'), false);
    assert.equal(isRecommendationReleased(undefined), false);
    assert.equal(isRecommendationReleased(null), false);
  });

  it('only approved and modified are released', () => {
    assert.equal(isRecommendationReleased('approved'), true);
    assert.equal(isRecommendationReleased('modified'), true);
  });

  it('athleteView omits recommendation prose while pending', () => {
    const view = buildAthleteRiskView(pendingLatest);
    assert.equal(view.recommendation, undefined);
    assert.equal(view.gradedOptions, undefined);
    assert.equal(view.reason, undefined);
    assert.equal(view.recommendationStatus, 'pending');
    assert.equal(view.riskLevel, 'HIGH');
  });

  it('athleteView still omits recommendation when rejected', () => {
    const view = buildAthleteRiskView({
      ...pendingLatest,
      recommendationStatus: 'rejected',
    });
    assert.equal(view.recommendation, undefined);
    assert.equal(isRecommendationReleased(view.recommendationStatus), false);
  });

  it('athleteView copies the plan only after approved', () => {
    const view = buildAthleteRiskView({
      ...pendingLatest,
      recommendationStatus: 'approved',
    });
    assert.equal(view.recommendation, pendingLatest.recommendation);
  });

  it('athleteView copies the plan after modified (Send to athlete)', () => {
    const view = buildAthleteRiskView({
      ...pendingLatest,
      recommendationStatus: 'modified',
      recommendation: 'Coach rewrite: easy spin only',
    });
    assert.equal(view.recommendation, 'Coach rewrite: easy spin only');
  });

  it('athlete is notified when the coach first approves (not on pending pipeline writes)', () => {
    assert.equal(
      shouldNotifyRecommendationRelease(
        { recommendationStatus: 'pending' },
        { recommendationStatus: 'approved' },
      ),
      true,
    );
    assert.equal(
      shouldNotifyRecommendationRelease(
        { recommendationStatus: 'pending' },
        { recommendationStatus: 'pending' },
      ),
      false,
    );
  });

  it('Ask AthleteIQ context does not include a pending recommendation', () => {
    const ctx = buildChatContext(
      [entry(AS_OF, 100)],
      {
        riskLevel: 'HIGH',
        confidence: 'Medium',
        reason: 'Load climbing',
        acwr: 1.6,
        trainingLoad7d: 400,
        trainingLoad28dAvg: 250,
        recoveryTrend: 'worsening',
        performancePrediction: 'DECLINING',
        performanceFrame: 'Slower time/pace',
        performanceFrameAxis: 'Time / pace',
      },
      'running',
      'Athlete A',
      {
        recommendation: 'Cut volume 20% — secret pending plan',
        recommendationStatus: 'pending',
      },
    );
    assert.equal(ctx.includes('secret pending plan'), false);
    assert.equal(ctx.includes('Latest recommendation:'), false);
  });

  it('Ask AthleteIQ context includes the plan only after approved', () => {
    const ctx = buildChatContext(
      [entry(AS_OF, 100)],
      {
        riskLevel: 'MEDIUM',
        confidence: 'Medium',
        reason: 'Load climbing',
        acwr: 1.4,
        trainingLoad7d: 350,
        trainingLoad28dAvg: 250,
        recoveryTrend: 'stable',
        performancePrediction: 'AVERAGE',
        performanceFrame: 'Typical time/pace',
        performanceFrameAxis: 'Time / pace',
      },
      'running',
      'Athlete A',
      {
        recommendation: 'Keep volume, drop intensity',
        recommendationStatus: 'approved',
      },
    );
    assert.equal(ctx.includes('Keep volume, drop intensity'), true);
  });
});
