import { calculateACWR, calculateFitnessFatigue, calculateRecoveryTrend, isFatiguePersistent, DailyEntry } from './calculations';

export type RiskLevel = 'LOW' | 'MEDIUM' | 'HIGH';
export type PerformancePrediction = 'GOOD' | 'AVERAGE' | 'DECLINING';

export interface RiskAssessment {
  riskLevel: RiskLevel;
  confidence: string;
  reason: string;
  acwr: number;
  trainingLoad7d: number;
  trainingLoad28dAvg: number;
  recoveryTrend: 'improving' | 'stable' | 'worsening';
  performancePrediction: PerformancePrediction;
}

/**
 * Section 13.4 — Step 5/6. This is intentionally simple, transparent
 * rule-based logic, NOT a black-box model — every branch here is one
 * the Explainability Agent (Section 6) can point straight back to.
 */
export function assessRisk(entriesRecentFirst: DailyEntry[]): RiskAssessment {
  const { acwr, acute7, chronicAvgWeekly } = calculateACWR(entriesRecentFirst);
  const { trend: recoveryTrend, usedHRV } = calculateRecoveryTrend(entriesRecentFirst);
  const fatiguePersistent = isFatiguePersistent(entriesRecentFirst);

  const entriesOldestFirst = [...entriesRecentFirst].reverse();
  const { performanceIndex } = calculateFitnessFatigue(entriesOldestFirst);

  // --- Step 5: rule-based combination ---
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
  };
}

function capitalize(s: string): string {
  return s.length ? s[0].toUpperCase() + s.slice(1) : s;
}
