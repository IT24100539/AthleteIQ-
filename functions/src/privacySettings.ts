/** Athlete privacySettings — missing keys default to shared (true). */

export interface PrivacySettings {
  wearableData: boolean;
  trainingLogs: boolean;
  injuryHistory: boolean;
  dailyFatigueCheckIn: boolean;
}

export const OPEN_PRIVACY: PrivacySettings = {
  wearableData: true,
  trainingLogs: true,
  injuryHistory: true,
  dailyFatigueCheckIn: true,
};

export function parsePrivacySettings(raw: unknown): PrivacySettings {
  const map =
    raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
  return {
    wearableData: map.wearableData !== false,
    trainingLogs: map.trainingLogs !== false,
    injuryHistory: map.injuryHistory !== false,
    dailyFatigueCheckIn: map.dailyFatigueCheckIn !== false,
  };
}

export function privacyAllShared(p: PrivacySettings): boolean {
  return p.wearableData && p.trainingLogs && p.injuryHistory && p.dailyFatigueCheckIn;
}

export function withheldLabels(p: PrivacySettings): string[] {
  const labels: string[] = [];
  if (!p.wearableData) labels.push('wearable data (heart rate, sleep, HRV)');
  if (!p.trainingLogs) labels.push('training logs (sessions, duration, intensity)');
  if (!p.injuryHistory) labels.push('injury history (pain reports)');
  if (!p.dailyFatigueCheckIn) labels.push('daily fatigue check-in');
  return labels;
}
