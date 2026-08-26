/**
 * Shared signal calculations used by both the Performance Model and the
 * Risk Model (Section 13.3 — "not fed separately, same raw data").
 *
 * Calendar windows (not check-in counts): 7-day / 28-day load, recovery
 * comparison, and persistent-fatigue look at real UTC calendar days ending
 * on `asOf`. A missed day is 0 training load. It is NOT skipped, so an
 * athlete who missed 3 days does not have their "7-day load" stretch across
 * 10 calendar days.
 *
 * Wellness averages (sleep, HRV, resting HR, fatigue): missing days and
 * null fields are excluded from the mean. They are never treated as 0 —
 * 0 hours of sleep is not a real logged value.
 *
 * All research-verified formulas are cited inline (Section 18.1):
 *  - Training Load = Duration × RPE (session-RPE method)
 *  - ACWR = 7-day acute load ÷ 28-day chronic average weekly load
 *  - Fitness/Fatigue = Banister impulse-response model
 */

export interface DailyEntry {
  date: string; // yyyy-mm-dd
  trainingLoad: number | null; // 0 on a logged rest day; missing day also sums as 0
  sleepHours: number | null;
  restingHeartRate: number | null;
  hrv: number | null;
  fatigueScore: number; // 1-5 when a check-in exists
  sessionSport?: string | null;
  sessionSportGroup?: string | null;
}

export interface CalendarDay {
  date: string;
  entry: DailyEntry | null;
}

function pad2(n: number): string {
  return String(n).padStart(2, '0');
}

/** UTC yyyy-mm-dd. */
export function utcDateKey(d = new Date()): string {
  return `${d.getUTCFullYear()}-${pad2(d.getUTCMonth() + 1)}-${pad2(d.getUTCDate())}`;
}

export function shiftDateKey(dateKey: string, deltaDays: number): string {
  const [y, m, day] = dateKey.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, day + deltaDays));
  return utcDateKey(dt);
}

function resolveAsOf(entries: DailyEntry[], asOf?: string): string {
  return asOf ?? entries[0]?.date ?? utcDateKey();
}

/** First occurrence wins — pass recent-first so duplicates keep the newest. */
export function indexEntriesByDate(entries: DailyEntry[]): Map<string, DailyEntry> {
  const map = new Map<string, DailyEntry>();
  for (const e of entries) {
    if (e.date && !map.has(e.date)) map.set(e.date, e);
  }
  return map;
}

/**
 * `days` UTC calendar days ending on `asOf` (inclusive), most-recent first.
 * Missing check-ins appear as `{ date, entry: null }`.
 */
export function calendarWindow(
  entries: DailyEntry[],
  days: number,
  asOf?: string,
): CalendarDay[] {
  const end = resolveAsOf(entries, asOf);
  const byDate = indexEntriesByDate(entries);
  const out: CalendarDay[] = [];
  for (let i = 0; i < days; i++) {
    const date = shiftDateKey(end, -i);
    out.push({ date, entry: byDate.get(date) ?? null });
  }
  return out;
}

/**
 * Mean of present numeric values. Null, undefined, and missing days are
 * omitted — never coerced to 0.
 */
export function averagePresent(values: Array<number | null | undefined>): number | null {
  const nums = values.filter((v): v is number => typeof v === 'number' && Number.isFinite(v));
  if (nums.length === 0) return null;
  return nums.reduce((a, b) => a + b, 0) / nums.length;
}

/** Sum of training load over the last N calendar days. Missing days = 0. */
export function sumLoad(entries: DailyEntry[], days: number, asOf?: string): number {
  return calendarWindow(entries, days, asOf).reduce(
    (sum, day) => sum + (day.entry?.trainingLoad ?? 0),
    0,
  );
}

/**
 * ACWR = acute (7-day calendar sum) ÷ chronic (28-day calendar sum ÷ 4).
 * Gabbett (2016) sweet spot: 0.8–1.3 low, >1.5 danger zone (Section 18.1 /
 * 18.2 — cited with the caveat that this figure has been contested).
 *
 * Section 18.4 — these ACWR cutoffs are fixed constants. They are NOT
 * loaded from coaches/{uid}/teamSettings.
 */
export function calculateACWR(
  entries: DailyEntry[],
  asOf?: string,
): { acwr: number; acute7: number; chronicAvgWeekly: number } {
  const acute7 = sumLoad(entries, 7, asOf);
  const chronic28Sum = sumLoad(entries, 28, asOf);
  const chronicAvgWeekly = chronic28Sum / 4;

  // Guard against div-by-zero for new athletes with no chronic baseline.
  const acwr = chronicAvgWeekly > 0 ? acute7 / chronicAvgWeekly : 1.0;

  return { acwr, acute7, chronicAvgWeekly };
}

/**
 * Simplified Banister Fitness-Fatigue model. Fitness decays slowly
 * (~42 days), Fatigue decays quickly (~7 days). Performance = Fitness − Fatigue.
 *
 * Each UTC calendar day from the oldest check-in through `asOf` is one
 * decay step. Missing days contribute 0 load but still decay — otherwise a
 * 3-day gap would be treated as three consecutive sessions.
 * `entries` may be in either order.
 */
export function calculateFitnessFatigue(
  entries: DailyEntry[],
  asOf?: string,
): {
  fitness: number;
  fatigue: number;
  performanceIndex: number;
} {
  const fitnessTau = 42;
  const fatigueTau = 7;
  let fitness = 0;
  let fatigue = 0;

  if (entries.length === 0) {
    return { fitness, fatigue, performanceIndex: 0 };
  }

  const byDate = indexEntriesByDate(entries);
  const dates = [...byDate.keys()].sort();
  const start = dates[0];
  const end = asOf ?? dates[dates.length - 1];
  if (end < start) {
    return { fitness, fatigue, performanceIndex: 0 };
  }

  for (let key = start; key <= end; key = shiftDateKey(key, 1)) {
    const load = byDate.get(key)?.trainingLoad ?? 0;
    fitness = fitness * Math.exp(-1 / fitnessTau) + load;
    fatigue = fatigue * Math.exp(-1 / fatigueTau) + load;
  }

  return { fitness, fatigue, performanceIndex: fitness - fatigue };
}

/**
 * Recovery trend: HRV-based if the athlete's device provides it
 * (Tier 1). Otherwise falls back to a rolling baseline built from
 * resting heart rate, sleep, and self-reported fatigue (Section 9 —
 * "recovery trend degrades gracefully" rather than blocking).
 *
 * Windows are 7 calendar days vs the prior 7 calendar days. Wellness
 * metrics average only logged values (see averagePresent).
 */
export function calculateRecoveryTrend(
  entriesRecentFirst: DailyEntry[],
  asOf?: string,
): {
  trend: 'improving' | 'stable' | 'worsening';
  usedHRV: boolean;
} {
  const last7 = calendarWindow(entriesRecentFirst, 7, asOf);
  const prev7 = calendarWindow(entriesRecentFirst, 14, asOf).slice(7, 14);

  const hrvRecent = averagePresent(last7.map((d) => d.entry?.hrv));
  const hrvPrior = averagePresent(prev7.map((d) => d.entry?.hrv));

  if (hrvRecent != null && hrvPrior != null && hrvPrior !== 0) {
    const change = (hrvRecent - hrvPrior) / hrvPrior;
    if (change > 0.05) return { trend: 'improving', usedHRV: true };
    if (change < -0.05) return { trend: 'worsening', usedHRV: true };
    return { trend: 'stable', usedHRV: true };
  }

  let worseVotes = 0;
  let betterVotes = 0;

  const rhrRecent = averagePresent(last7.map((d) => d.entry?.restingHeartRate));
  const rhrPrior = averagePresent(prev7.map((d) => d.entry?.restingHeartRate));
  if (rhrRecent != null && rhrPrior != null && rhrPrior !== 0) {
    if (rhrRecent > rhrPrior * 1.03) worseVotes++;
    else if (rhrRecent < rhrPrior * 0.97) betterVotes++;
  }

  const sleepRecent = averagePresent(last7.map((d) => d.entry?.sleepHours));
  const sleepPrior = averagePresent(prev7.map((d) => d.entry?.sleepHours));
  if (sleepRecent != null && sleepPrior != null) {
    if (sleepRecent < sleepPrior - 0.5) worseVotes++;
    else if (sleepRecent > sleepPrior + 0.5) betterVotes++;
  }

  const fatigueRecent = averagePresent(last7.map((d) => d.entry?.fatigueScore));
  const fatiguePrior = averagePresent(prev7.map((d) => d.entry?.fatigueScore));
  if (fatigueRecent != null && fatiguePrior != null) {
    if (fatigueRecent > fatiguePrior + 0.4) worseVotes++;
    else if (fatigueRecent < fatiguePrior - 0.4) betterVotes++;
  }

  if (worseVotes > betterVotes) return { trend: 'worsening', usedHRV: false };
  if (betterVotes > worseVotes) return { trend: 'improving', usedHRV: false };
  return { trend: 'stable', usedHRV: false };
}

/**
 * Fatigue staying elevated for several days (Step 4).
 * True only when each of the last 4 calendar days has a check-in and
 * every fatigueScore is >= 4. A gap breaks the streak — we do not invent
 * a fatigue value for a missed day.
 */
export function isFatiguePersistent(entriesRecentFirst: DailyEntry[], asOf?: string): boolean {
  const last4 = calendarWindow(entriesRecentFirst, 4, asOf);
  if (last4.length < 4) return false;
  return last4.every((day) => day.entry != null && day.entry.fatigueScore >= 4);
}
