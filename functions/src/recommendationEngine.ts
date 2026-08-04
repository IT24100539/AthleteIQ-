import { RiskLevel, PerformancePrediction } from './riskModel';

export type SportGroup =
  | 'endurance'
  | 'teamContact'
  | 'strengthPower'
  | 'skillPrecision'
  | 'combat'
  | 'other';

type ActionTemplate = Record<RiskLevel, string>;

/**
 * Section 15.3 — same underlying decision logic for every sport; only
 * the wording changes so advice sounds relevant instead of generic.
 * New sports slot into an existing group here — no new model needed
 * (Section 12.4 / 15.3).
 */
const SPORT_TEMPLATES: Record<SportGroup, ActionTemplate> = {
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
    MEDIUM: 'Reduce load 15\u201320% on today\u2019s lifts, keep technique sharp.',
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
    HIGH: 'Reduce training volume by 20% this week, add one extra rest day.',
    MEDIUM: 'Keep training but reduce intensity slightly.',
    LOW: 'Continue training as planned.',
  },
};

export interface Recommendation {
  action: string;
  orchestratorNote: string;
}

/**
 * Section 6 (Orchestrator) + Section 15.2 — risk always outranks
 * performance ("protecting the athlete comes first"), and this
 * function is the one place that decision is made.
 */
export function buildRecommendation(
  riskLevel: RiskLevel,
  performancePrediction: PerformancePrediction,
  sportGroup: SportGroup,
): Recommendation {
  const template = SPORT_TEMPLATES[sportGroup] ?? SPORT_TEMPLATES.other;

  if (riskLevel === 'HIGH' || riskLevel === 'MEDIUM') {
    return {
      action: template[riskLevel],
      orchestratorNote:
        performancePrediction === 'GOOD'
          ? 'Performance looked strong this week, but risk takes priority \u2014 protecting the athlete comes first.'
          : 'Risk signals took priority in this decision.',
    };
  }

  // LOW risk: performance prediction breaks the tie (Section 15.2 Step 3).
  if (performancePrediction === 'DECLINING') {
    return {
      action: 'Consider a small deload \u2014 check in on sleep and fatigue trends.',
      orchestratorNote: 'Risk is low, but performance is trending down \u2014 worth a light check-in.',
    };
  }

  return {
    action: template.LOW,
    orchestratorNote: 'Risk is low and performance looks on track.',
  };
}
