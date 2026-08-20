import { calculateACWR, calculateFitnessFatigue, calculateRecoveryTrend, isFatiguePersistent, DailyEntry } from './calculations';
import type { SportGroup } from './recommendationEngine';

export type RiskLevel = 'LOW' | 'MEDIUM' | 'HIGH';
export type PerformancePrediction = 'GOOD' | 'AVERAGE' | 'DECLINING';

const SPORT_GROUPS: SportGroup[] = [
  'endurance',
  'teamContact',
  'strengthPower',
  'skillPrecision',
  'combat',
  'other',
];

export function resolveSportGroup(raw?: string | null): SportGroup {
  return SPORT_GROUPS.includes(raw as SportGroup) ? (raw as SportGroup) : 'other';
}

/**
 * Section 12.3 — same Banister band (GOOD / AVERAGE / DECLINING) for
 * every sport; only the phrasing changes. Config lookup, not a
 * separate performance model per group (mirrors Section 12.4 templates).
 */
export interface PerformanceFrame {
  axis: string;
  GOOD: string;
  AVERAGE: string;
  DECLINING: string;
}

export const PERFORMANCE_FRAMES: Record<SportGroup, PerformanceFrame> = {
  endurance: {
    axis: 'Time / pace',
    GOOD: 'Strong time/pace',
    AVERAGE: 'Typical time/pace',
    DECLINING: 'Slower time/pace',
  },
  teamContact: {
    axis: 'Coach readiness',
    GOOD: 'High coach-rated readiness',
    AVERAGE: 'Typical coach-rated readiness',
    DECLINING: 'Lower coach-rated readiness',
  },
  strengthPower: {
    axis: 'Max output',
    GOOD: 'Strong max output',
    AVERAGE: 'Typical max output',
    DECLINING: 'Lower max output',
  },
  skillPrecision: {
    axis: 'Match + readiness',
    GOOD: 'Strong match + readiness',
    AVERAGE: 'Typical match + readiness',
    DECLINING: 'Weaker match + readiness',
  },
  combat: {
    axis: 'Readiness + sparring',
    GOOD: 'High readiness / sparring',
    AVERAGE: 'Typical readiness / sparring',
    DECLINING: 'Lower readiness / sparring',
  },
  other: {
    axis: 'Performance',
    GOOD: 'GOOD',
    AVERAGE: 'AVERAGE',
    DECLINING: 'DECLINING',
  },
};

export function phrasePerformance(
  sportGroup: SportGroup | string | null | undefined,
  band: PerformancePrediction,
): { axis: string; label: string } {
  const frame = PERFORMANCE_FRAMES[resolveSportGroup(sportGroup ?? undefined)];
  const safe: PerformancePrediction =
    band === 'GOOD' || band === 'DECLINING' ? band : 'AVERAGE';
  return { axis: frame.axis, label: frame[safe] };
}

export interface RiskAssessment {
  riskLevel: RiskLevel;
  confidence: string;
  reason: string;
  acwr: number;
  trainingLoad7d: number;
  trainingLoad28dAvg: number;
  recoveryTrend: 'improving' | 'stable' | 'worsening';
  /** Canonical band — orchestrator / rules still key off this. */
  performancePrediction: PerformancePrediction;
  /** Section 12.3 sport-group phrasing of the same band. */
  performanceFrame: string;
  performanceFrameAxis: string;
}

/**
 * Section 13.4 — Step 5/6. This is intentionally simple, transparent
 * rule-based logic, NOT a black-box model — every branch here is one
 * the Explainability Agent (Section 6) can point straight back to.
 *
 * Hybrid principle (Section 14.5): assessRisk() owns the classification.
 * Thresholds below must not be "softened" by an LLM. After this function
 * returns, explainabilityLlm.ts may write richer prose into
 * riskLevelReasoningLLM / performanceReasoningLLM, but riskLevel and
 * performancePrediction stay exactly what this function produced.
 *
 * Section 12.3: pass sportGroup only to phrase the locked band. The
 * Banister / recovery rules do not change by sport.
 */
export function assessRisk(
  entriesRecentFirst: DailyEntry[],
  sportGroup?: SportGroup | string | null,
): RiskAssessment {
  const { acwr, acute7, chronicAvgWeekly } = calculateACWR(entriesRecentFirst);
  const { trend: recoveryTrend, usedHRV } = calculateRecoveryTrend(entriesRecentFirst);
  const fatiguePersistent = isFatiguePersistent(entriesRecentFirst);

  const entriesOldestFirst = [...entriesRecentFirst].reverse();
  const { performanceIndex } = calculateFitnessFatigue(entriesOldestFirst);

  // --- Step 5: rule-based combination ---
  // Section 18.4 — ACWR thresholds below (1.5 / 1.3 / 0.8–1.3) are fixed
  // research-backed constants. They are NOT coach-adjustable via
  // teamSettings; only recommendation load-reduction *wording* (e.g. 20%)
  // is tunable per coach in recommendationEngine.ts.
  let riskLevel: RiskLevel;
  const reasons: string[] = [];

  if (acwr > 1.5 && recoveryTrend === 'worsening' && fatiguePersistent) {
    riskLevel = 'HIGH';
    reasons.push(`training load spiked (ACWR ${acwr.toFixed(2)}, above the 1.5 danger threshold)`);
    reasons.push('recovery is trending worse');
    reasons.push('fatigue has stayed elevated for several days');
  } else if (acwr >= 0.8 && acwr <= 1.3 && recoveryTrend === 'stable') {
    riskLevel = 'LOW';
    reasons.push(`training load is in the stable range (ACWR ${acwr.toFixed(2)})`);
    reasons.push('recovery looks stable');
  } else {
    riskLevel = 'MEDIUM';
    if (acwr > 1.3) reasons.push(`training load is climbing (ACWR ${acwr.toFixed(2)})`);
    if (recoveryTrend === 'worsening') reasons.push('recovery is trending down');
    if (fatiguePersistent) reasons.push('fatigue has been elevated the last few days');
    if (reasons.length === 0) reasons.push('signals are mixed and don\u2019t clearly fall in the low-risk range');
  }

  // --- Performance prediction, independent read of the same numbers ---
  let performancePrediction: PerformancePrediction;
  if (performanceIndex > 0 && recoveryTrend !== 'worsening') {
    performancePrediction = 'GOOD';
  } else if (performanceIndex < 0 || fatiguePersistent) {
    performancePrediction = 'DECLINING';
  } else {
    performancePrediction = 'AVERAGE';
  }

  const framed = phrasePerformance(sportGroup, performancePrediction);

  const confidence = usedHRV
    ? 'High (HRV available)'
    : 'Medium (HRV not available for this athlete)';

  return {
    riskLevel,
    confidence,
    reason: capitalize(reasons.join('; ')) + '.',
    acwr,
    trainingLoad7d: acute7,
    trainingLoad28dAvg: chronicAvgWeekly,
    recoveryTrend,
    performancePrediction,
    performanceFrame: framed.label,
    performanceFrameAxis: framed.axis,
  };
}

function capitalize(s: string): string {
  return s.length ? s[0].toUpperCase() + s.slice(1) : s;
}
