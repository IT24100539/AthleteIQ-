import { DailyEntry } from './calculations';
import { CheckInLoader } from './checkInLoader';
import { SportGroup } from './recommendationEngine';

function series(
  days: number,
  row: (i: number) => Omit<DailyEntry, 'date'>,
): DailyEntry[] {
  const origin = new Date(Date.UTC(2026, 7, 15));
  return Array.from({ length: days }, (_, i) => {
    const d = new Date(origin);
    d.setUTCDate(origin.getUTCDate() - i);
    return { date: d.toISOString().slice(0, 10), ...row(i) };
  });
}

export interface FixtureAthlete {
  id: string;
  name: string;
  sportGroup: SportGroup;
  expectedRisk: 'LOW' | 'MEDIUM' | 'HIGH';
  story: string;
  entries: DailyEntry[];
}

/** HIGH risk: ACWR spike + worsening HRV + persistent fatigue. */
const mayaSpike: FixtureAthlete = {
  id: 'fixture-maya-spike',
  name: 'Maya (spike)',
  sportGroup: 'endurance',
  expectedRisk: 'HIGH',
  story: 'Last week doubled volume; HRV crashed; fatigue stuck at 4+.',
  entries: series(28, (i) =>
    i < 7
      ? {
          trainingLoad: 80 * 8,
          sleepHours: 5.5,
          restingHeartRate: 62,
          hrv: 32,
          fatigueScore: 4,
        }
      : {
          trainingLoad: 30 * 4,
          sleepHours: 7.6,
          restingHeartRate: 50,
          hrv: 58,
          fatigueScore: 2,
        },
  ),
};

/** MEDIUM risk + GOOD performance — the conflict the old if/else always gives to risk. */
const arthurClimb: FixtureAthlete = {
  id: 'fixture-arthur-climb',
  name: 'Arthur (climb)',
  sportGroup: 'endurance',
  expectedRisk: 'MEDIUM',
  story: 'Load climbed this week, recovery still stable, Banister index still good.',
  entries: series(28, (i) =>
    i < 7
      ? {
          trainingLoad: 60 * 4,
          sleepHours: 7.4,
          restingHeartRate: 51,
          hrv: 52,
          fatigueScore: 2,
        }
      : {
          trainingLoad: 40 * 4,
          sleepHours: 7.5,
          restingHeartRate: 50,
          hrv: 53,
          fatigueScore: 2,
        },
  ),
};

/** LOW risk, steady training — continue as planned. */
const jordanSteady: FixtureAthlete = {
  id: 'fixture-jordan-steady',
  name: 'Jordan (steady)',
  sportGroup: 'endurance',
  expectedRisk: 'LOW',
  story: 'Four weeks of the same easy volume; sleep and HRV flat.',
  entries: series(28, () => ({
    trainingLoad: 40 * 4,
    sleepHours: 7.5,
    restingHeartRate: 50,
    hrv: 52,
    fatigueScore: 2,
  })),
};

/** MEDIUM / ambiguous: ACWR in range but recovery worsening. */
const samAmbiguous: FixtureAthlete = {
  id: 'fixture-sam-ambiguous',
  name: 'Sam (ambiguous)',
  sportGroup: 'endurance',
  expectedRisk: 'MEDIUM',
  story: 'Load looks fine on paper but HRV and sleep dropped this week.',
  entries: series(28, (i) =>
    i < 7
      ? {
          trainingLoad: 40 * 4,
          sleepHours: 5.8,
          restingHeartRate: 58,
          hrv: 36,
          fatigueScore: 3,
        }
      : {
          trainingLoad: 40 * 4,
          sleepHours: 7.6,
          restingHeartRate: 50,
          hrv: 55,
          fatigueScore: 2,
        },
  ),
};

export const ORCHESTRATOR_FIXTURES: FixtureAthlete[] = [
  mayaSpike,
  arthurClimb,
  jordanSteady,
  samAmbiguous,
];

export function fixtureCheckInLoader(): CheckInLoader {
  const byId = new Map(ORCHESTRATOR_FIXTURES.map((f) => [f.id, f.entries]));
  return async (athleteUid, days) => {
    const entries = byId.get(athleteUid);
    if (!entries) return [];
    return entries.slice(0, days);
  };
}
