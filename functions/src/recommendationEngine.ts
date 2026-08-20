import { RiskLevel, PerformancePrediction } from './riskModel';

export type SportGroup =
  | 'endurance'
  | 'teamContact'
  | 'strengthPower'
  | 'skillPrecision'
  | 'combat'
  | 'other';

type ActionTemplate = Record<RiskLevel, string>;

/** Section 18.4 — coach-adjustable via teamSettings (10–30%). Default 20%. */
export const DEFAULT_ACTION_PERCENT = 20;
export const MIN_ACTION_PERCENT = 10;
export const MAX_ACTION_PERCENT = 30;

/**
 * Section 18.4 — only recommendation *wording* percentages are coach-tunable.
 * ACWR cutoffs (1.5 danger, 1.3 climb, 0.8–1.3 stable band) stay fixed in
 * riskModel.ts / calculations.ts — research-backed, not teamSettings.
 */
export function clampActionPercent(raw: unknown): number {
  const n =
    typeof raw === 'number' && Number.isFinite(raw)
      ? raw
      : DEFAULT_ACTION_PERCENT;
  return Math.min(MAX_ACTION_PERCENT, Math.max(MIN_ACTION_PERCENT, Math.round(n)));
}

/**
 * Section 15.3 — same underlying decision logic for every sport; only
 * the wording changes so advice sounds relevant instead of generic.
 * Section 18.4 — HIGH-risk load-reduction text uses defaultActionPercent.
 */
export function buildSportTemplates(
  defaultActionPercent: number = DEFAULT_ACTION_PERCENT,
): Record<SportGroup, ActionTemplate> {
  const pct = clampActionPercent(defaultActionPercent);
  const mediumLow = Math.max(MIN_ACTION_PERCENT, pct - 5);

  return {
    endurance: {
      HIGH: 'Easy recovery session only, no intervals or race-pace work this week.',
      MEDIUM: 'Keep the volume but drop the intensity — easy pace, skip the hard set.',
      LOW: 'Continue training as planned.',
    },
    teamContact: {
      HIGH: 'No contact training today — light conditioning only, sit out scrimmage.',
      MEDIUM: 'Train, but reduce contact drills and live reps today.',
      LOW: 'Continue training as planned.',
    },
    strengthPower: {
      HIGH: 'Skip today\u2019s heavy session — light technical work or full rest.',
      MEDIUM: `Reduce load ${mediumLow}\u2013${pct}% on today\u2019s lifts, keep technique sharp.`,
      LOW: 'Continue training as planned.',
    },
    skillPrecision: {
      HIGH: 'Light footwork/technical work only \u2014 no match play today.',
      MEDIUM: 'Reduce match intensity, add more recovery between games.',
      LOW: 'Continue training as planned.',
    },
    combat: {
      HIGH: 'No sparring today \u2014 mobility and technical drilling only.',
      MEDIUM: 'Light sparring only, reduce rounds and contact intensity.',
      LOW: 'Continue training as planned.',
    },
    other: {
      HIGH: `Reduce training volume by ${pct}% this week, add one extra rest day.`,
      MEDIUM: 'Keep training but reduce intensity slightly.',
      LOW: 'Continue training as planned.',
    },
  };
}

/** Default templates at 20% — tests and static references. */
export const SPORT_TEMPLATES = buildSportTemplates(DEFAULT_ACTION_PERCENT);

export interface Recommendation {
  action: string;
  orchestratorNote: string;
  /** Set by `describeOrchestratorConflict()` — do not re-derive in the UI. */
  conflict: OrchestratorConflict;
}

/**
 * Section 6 + 15.2 — when risk and performance disagree, this is the
 * source of truth for *whether* there is a conflict, *who won*, and *why*.
 * `buildRecommendation()` calls this; the Flutter conflict screen reads
 * the stored copy. Do not re-implement these branches in the client.
 */
export type OrchestratorConflictKind =
  | 'none'
  | 'elevated_risk_vs_strong_performance'
  | 'low_risk_vs_declining_performance';

export type OrchestratorConflictWinner = 'risk' | 'performance' | 'aligned';

export interface OrchestratorConflict {
  present: boolean;
  kind: OrchestratorConflictKind;
  winner: OrchestratorConflictWinner;
  winnerLabel: string;
  why: string;
  riskLevel: RiskLevel;
  performancePrediction: PerformancePrediction;
}

export function describeOrchestratorConflict(
  riskLevel: RiskLevel,
  performancePrediction: PerformancePrediction,
): OrchestratorConflict {
  const base = { riskLevel, performancePrediction };

  // Elevated risk + strong performance: risk always outranks (Section 15.2).
  if (
    (riskLevel === 'HIGH' || riskLevel === 'MEDIUM') &&
    performancePrediction === 'GOOD'
  ) {
    return {
      ...base,
      present: true,
      kind: 'elevated_risk_vs_strong_performance',
      winner: 'risk',
      winnerLabel: 'Risk',
      why: 'Performance looked strong this week, but risk takes priority \u2014 protecting the athlete comes first.',
    };
  }

  // LOW risk: performance prediction breaks the tie (Section 15.2 Step 3).
  if (riskLevel === 'LOW' && performancePrediction === 'DECLINING') {
    return {
      ...base,
      present: true,
      kind: 'low_risk_vs_declining_performance',
      winner: 'performance',
      winnerLabel: 'Performance (tie-break)',
      why: 'Risk is low, but performance is trending down \u2014 worth a light check-in.',
    };
  }

  return {
    ...base,
    present: false,
    kind: 'none',
    winner: 'aligned',
    winnerLabel: 'Aligned',
    why:
      riskLevel === 'HIGH' || riskLevel === 'MEDIUM'
        ? 'Risk signals took priority in this decision.'
        : 'Risk is low and performance looks on track.',
  };
}

export const LOW_DECLINING_ACTION =
  'Consider a small deload \u2014 check in on sleep and fatigue trends.';

/** Sport-specific action strings the agent should choose from. */
export function recommendationOptions(
  sportGroup: SportGroup,
  defaultActionPercent: number = DEFAULT_ACTION_PERCENT,
): {
  HIGH: string;
  MEDIUM: string;
  LOW: string;
  LOW_DECLINING: string;
} {
  const template =
    buildSportTemplates(defaultActionPercent)[sportGroup] ?? SPORT_TEMPLATES.other;
  return {
    HIGH: template.HIGH,
    MEDIUM: template.MEDIUM,
    LOW: template.LOW,
    LOW_DECLINING: LOW_DECLINING_ACTION,
  };
}

/**
 * @deprecated Rule-based Orchestrator (Section 15.2). Kept only as a
 * comparison baseline. Live decisions go through `runOrchestratorAgent()`
 * in orchestratorAgent.ts. The pipeline still calls this so we can store
 * `ruleBasedRecommendation` next to the agent's choice.
 *
 * Section 6 + 15.2 — risk always outranks performance.
 */
export function buildRecommendation(
  riskLevel: RiskLevel,
  performancePrediction: PerformancePrediction,
  sportGroup: SportGroup,
  defaultActionPercent: number = DEFAULT_ACTION_PERCENT,
): Recommendation {
  const template =
    buildSportTemplates(defaultActionPercent)[sportGroup] ?? SPORT_TEMPLATES.other;
  const conflict = describeOrchestratorConflict(riskLevel, performancePrediction);

  if (riskLevel === 'HIGH' || riskLevel === 'MEDIUM') {
    return {
      action: template[riskLevel],
      orchestratorNote: conflict.why,
      conflict,
    };
  }

  // LOW risk: performance prediction breaks the tie (Section 15.2 Step 3).
  if (performancePrediction === 'DECLINING') {
    return {
      action: LOW_DECLINING_ACTION,
      orchestratorNote: conflict.why,
      conflict,
    };
  }

  return {
    action: template.LOW,
    orchestratorNote: conflict.why,
    conflict,
  };
}
