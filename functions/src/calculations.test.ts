/**
 * Calendar-day ACWR / load windows. The old implementation sliced the last
 * N check-in documents; a 3-day gap made "7-day load" span 10 real days.
 */
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  averagePresent,
  calculateACWR,
  calculateRecoveryTrend,
  DailyEntry,
  isFatiguePersistent,
  sumLoad,
} from './calculations';

/** Pre-fix behavior: last N check-in documents, gaps ignored. */
function legacySumLoad(entries: DailyEntry[], days: number): number {
  return entries.slice(0, days).reduce((sum, e) => sum + (e.trainingLoad ?? 0), 0);
}

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
 * asOf = 2026-08-21.
 * Logged days: 21, 20, 19, then a 3-day gap (18/17/16), then 15, 14, 13, 12…
 * Recent-first, 28 check-ins would have stretched further back; we only
 * log 10 days so the document-slice vs calendar-window difference is obvious.
 */
function gappedAthlete(): DailyEntry[] {
  const logged: Array<[string, number]> = [
    ['2026-08-21', 100],
    ['2026-08-20', 100],
    ['2026-08-19', 100],
    // gap: 18, 17, 16
    ['2026-08-15', 100],
    ['2026-08-14', 100],
    ['2026-08-13', 100],
    ['2026-08-12', 100],
    ['2026-08-11', 50],
    ['2026-08-10', 50],
    ['2026-08-09', 50],
    ['2026-08-08', 50],
    ['2026-08-07', 50],
    ['2026-08-06', 50],
    ['2026-08-05', 50],
    ['2026-08-04', 50],
    ['2026-08-03', 50],
    ['2026-08-02', 50],
    ['2026-08-01', 50],
    ['2026-07-31', 50],
    ['2026-07-30', 50],
    ['2026-07-29', 50],
    ['2026-07-28', 50],
    ['2026-07-27', 50],
    ['2026-07-26', 50],
    ['2026-07-25', 50],
  ];
  return logged.map(([date, load]) => entry(date, load));
}

describe('calendar-day training load / ACWR', () => {
  const asOf = '2026-08-21';
  const entries = gappedAthlete();

  it('before (document slice) vs after (calendar days) on a 3-day gap', () => {
    const before7 = legacySumLoad(entries, 7);
    const after7 = sumLoad(entries, 7, asOf);

    // Last 7 *documents*: 21,20,19,15,14,13,12 → 100×7 = 700, spanning 10 calendar days.
    assert.equal(before7, 700);
    // Last 7 *calendar* days: 21,20,19, 18,17,16, 15 → 100+100+100+0+0+0+100 = 400.
    assert.equal(after7, 400);

    const before28 = legacySumLoad(entries, 28);
    const after28 = sumLoad(entries, 28, asOf);
    // Document slice still sums every logged row (25 docs) because there are <28.
    assert.equal(before28, 100 * 7 + 50 * 18);
    // Calendar 28 days (Jul 25–Aug 21) includes the 3-day gap as 0, and does not
    // pull extra documents from before the window. Jul 25 is logged (50).
    // Logged in window: 21–19 (100×3), 15–12 (100×4), 11–Jul 25 (50×18) = 700+900=1600.
    // Wait: Jul 25 is 27 days before Aug 21? Aug 21-27 = Jul 25. 28 days inclusive:
    // Aug 21 back 27 days = Jul 25. Yes Jul 25 is in window.
    // Gap days 16–18 not in the logged list so they add 0.
    // Same logged loads as before28 except we must not include anything before Jul 25.
    // Oldest logged is Jul 25, all 25 docs fall inside the 28-day window, plus 3 zeros.
    assert.equal(after28, before28);
    assert.ok(after7 < before7, 'acute window must shrink when gaps are zeros, not skipped');
  });

  it('ACWR uses calendar acute/chronic, not check-in counts', () => {
    const { acwr, acute7, chronicAvgWeekly } = calculateACWR(entries, asOf);
    assert.equal(acute7, 400);
    assert.equal(chronicAvgWeekly, (100 * 7 + 50 * 18) / 4);
    assert.equal(acwr, acute7 / chronicAvgWeekly);

    const legacyAcute = legacySumLoad(entries, 7);
    const legacyChronic = legacySumLoad(entries, 28) / 4;
    const legacyAcwr = legacyAcute / legacyChronic;
    assert.ok(legacyAcwr > acwr, 'document-slice ACWR was inflated by skipping the gap');
  });

  it('logged rest days stay 0; missing days are also 0 (not skipped)', () => {
    const rest: DailyEntry[] = [
      entry('2026-08-21', 200),
      { ...entry('2026-08-20', 0), trainingLoad: 0 },
      entry('2026-08-18', 200),
    ];
    // Calendar 7 ending 21st: 21=200, 20=0 (logged rest), 19=missing 0, 18=200, 17–15 missing 0.
    assert.equal(sumLoad(rest, 7, '2026-08-21'), 400);
  });
});

describe('wellness averages skip missing days (not 0)', () => {
  it('averagePresent omits nulls instead of treating them as 0 sleep', () => {
    assert.equal(averagePresent([8, null, 6]), 7);
    assert.equal(averagePresent([null, undefined]), null);
  });

  it('recovery trend does not invent fatigue/sleep for a gap', () => {
    // 7 recent calendar days: only two sleep logs (8h). Prior week: two 6h logs.
    // If gaps were 0, recent average would collapse and look like worsening sleep.
    const entries: DailyEntry[] = [
      entry('2026-08-21', 100, { sleepHours: 8, hrv: null, restingHeartRate: null, fatigueScore: 2 }),
      entry('2026-08-15', 100, { sleepHours: 8, hrv: null, restingHeartRate: null, fatigueScore: 2 }),
      entry('2026-08-10', 100, { sleepHours: 6, hrv: null, restingHeartRate: null, fatigueScore: 2 }),
      entry('2026-08-08', 100, { sleepHours: 6, hrv: null, restingHeartRate: null, fatigueScore: 2 }),
    ];
    const { trend, usedHRV } = calculateRecoveryTrend(entries, '2026-08-21');
    assert.equal(usedHRV, false);
    // Recent sleep avg = 8 (only 21st in last 7; 15th is the 7th day actually:
    // 21,20,19,18,17,16,15 → 21 and 15 both in window, avg 8.
    // Prior 14–8: 10 and 8, avg 6. Sleep improved by 2h → improving vote.
    assert.equal(trend, 'improving');
  });

  it('persistent fatigue requires four logged calendar days, not four documents across a gap', () => {
    const entries: DailyEntry[] = [
      entry('2026-08-21', 100, { fatigueScore: 5 }),
      entry('2026-08-20', 100, { fatigueScore: 5 }),
      entry('2026-08-19', 100, { fatigueScore: 5 }),
      // gap on 18
      entry('2026-08-17', 100, { fatigueScore: 5 }),
    ];
    assert.equal(isFatiguePersistent(entries, '2026-08-21'), false);
    const consecutive = [
      entry('2026-08-21', 100, { fatigueScore: 5 }),
      entry('2026-08-20', 100, { fatigueScore: 4 }),
      entry('2026-08-19', 100, { fatigueScore: 4 }),
      entry('2026-08-18', 100, { fatigueScore: 4 }),
    ];
    assert.equal(isFatiguePersistent(consecutive, '2026-08-21'), true);
  });
});
