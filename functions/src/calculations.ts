/**
 * Shared signal calculations used by both the Performance Model and the
 * Risk Model (Section 13.3 — "not fed separately, same raw data").
 *
 * All research-verified formulas are cited inline (Section 18.1):
 *  - Training Load = Duration × RPE (session-RPE method)
 *  - ACWR = 7-day acute load ÷ 28-day chronic average weekly load
 *  - Fitness/Fatigue = Banister impulse-response model
 */

export interface DailyEntry {
  date: string; // yyyy-mm-dd
  trainingLoad: number | null; // null on rest/no-session days
  sleepHours: number | null;
  restingHeartRate: number | null;
  hrv: number | null;
  fatigueScore: number; // 1-5, always present (daily check-in is required)
}

/** Sum of training load over the most recent N days (inclusive of today). */
export function sumLoad(entries: DailyEntry[], days: number): number {
  const recent = entries.slice(0, days);
  return recent.reduce((sum, e) => sum + (e.trainingLoad ?? 0), 0);
}

/**
 * ACWR = acute (7-day sum) ÷ chronic (28-day sum ÷ 4, i.e. average
 * weekly load over the last 4 weeks). Gabbett (2016) sweet spot:
 * 0.8–1.3 low, >1.5 danger zone (Section 18.1 / 18.2 — cited with the
 * caveat that this figure has been contested in the literature).
 */
export function calculateACWR(entries: DailyEntry[]): { acwr: number; acute7: number; chronicAvgWeekly: number } {
  const acute7 = sumLoad(entries, 7);
  const chronic28Sum = sumLoad(entries, 28);
  const chronicAvgWeekly = chronic28Sum / 4;

  // Guard against div-by-zero for new athletes with <4 weeks of data —
  // treat as neutral (1.0) rather than throwing, since a brand-new
  // athlete legitimately has no chronic baseline yet.
  const acwr = chronicAvgWeekly > 0 ? acute7 / chronicAvgWeekly : 1.0;

  return { acwr, acute7, chronicAvgWeekly };
}

/**
 * Simplified Banister Fitness-Fatigue model. Fitness decays slowly
 * (long time constant ~42 days), Fatigue decays quickly (~7 days).
 * Performance = Fitness − Fatigue. `entries` must be sorted oldest→newest.
 */
export function calculateFitnessFatigue(entriesOldestFirst: DailyEntry[]): {
  fitness: number;
  fatigue: number;
  performanceIndex: number;
} {
  const fitnessTau = 42;
  const fatigueTau = 7;
  let fitness = 0;
  let fatigue = 0;

  for (const e of entriesOldestFirst) {
    const load = e.trainingLoad ?? 0;
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
 */
export function calculateRecoveryTrend(entriesRecentFirst: DailyEntry[]): {
  trend: 'improving' | 'stable' | 'worsening';
  usedHRV: boolean;
} {
  const last7 = entriesRecentFirst.slice(0, 7);
  const prev7 = entriesRecentFirst.slice(7, 14);

  const hasHRV = last7.some((e) => e.hrv !== null) && prev7.some((e) => e.hrv !== null);

  if (hasHRV) {
    const avg = (arr: DailyEntry[]) => avgOf(arr.map((e) => e.hrv).filter((v): v is number => v !== null));
    const recent = avg(last7);
    const prior = avg(prev7);
    if (prior === 0) return { trend: 'stable', usedHRV: true };
    const change = (recent - prior) / prior;
    // HRV rising = recovering better; falling = worse recovery.
    if (change > 0.05) return { trend: 'improving', usedHRV: true };
    if (change < -0.05) return { trend: 'worsening', usedHRV: true };
    return { trend: 'stable', usedHRV: true };
  }

  // Fallback: resting HR (rising = worse), sleep (falling = worse),
  // fatigue (rising = worse). Each contributes one "vote".
  let worseVotes = 0;
  let betterVotes = 0;

  const rhrRecent = avgOf(last7.map((e) => e.restingHeartRate).filter((v): v is number => v !== null));
  const rhrPrior = avgOf(prev7.map((e) => e.restingHeartRate).filter((v): v is number => v !== null));
  if (rhrRecent && rhrPrior) {
    if (rhrRecent > rhrPrior * 1.03) worseVotes++;
    else if (rhrRecent < rhrPrior * 0.97) betterVotes++;
  }

  const sleepRecent = avgOf(last7.map((e) => e.sleepHours).filter((v): v is number => v !== null));
  const sleepPrior = avgOf(prev7.map((e) => e.sleepHours).filter((v): v is number => v !== null));
  if (sleepRecent && sleepPrior) {
    if (sleepRecent < sleepPrior - 0.5) worseVotes++;
    else if (sleepRecent > sleepPrior + 0.5) betterVotes++;
  }

  const fatigueRecent = avgOf(last7.map((e) => e.fatigueScore));
  const fatiguePrior = avgOf(prev7.map((e) => e.fatigueScore));
  if (fatiguePrior) {
    if (fatigueRecent > fatiguePrior + 0.4) worseVotes++;
    else if (fatigueRecent < fatiguePrior - 0.4) betterVotes++;
  }

  if (worseVotes > betterVotes) return { trend: 'worsening', usedHRV: false };
  if (betterVotes > worseVotes) return { trend: 'improving', usedHRV: false };
  return { trend: 'stable', usedHRV: false };
}

/** Is Fatigue staying elevated for several days instead of clearing? (Step 4) */
export function isFatiguePersistent(entriesRecentFirst: DailyEntry[]): boolean {
  const last4 = entriesRecentFirst.slice(0, 4);
  if (last4.length < 4) return false;
  return last4.every((e) => e.fatigueScore >= 4);
}

function avgOf(nums: number[]): number {
  if (nums.length === 0) return 0;
  return nums.reduce((a, b) => a + b, 0) / nums.length;
}
