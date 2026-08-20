import { DocumentData, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { DailyEntry } from './calculations';

export function entryFromCheckInDoc(id: string, data: DocumentData): DailyEntry {
  const durationMin = data.sessionDurationMinutes ?? 0;
  const rpe = data.rpe ?? 0;
  return {
    date: /^\d{4}-\d{2}-\d{2}$/.test(id) ? id : id,
    trainingLoad: durationMin * rpe,
    sleepHours: data.sleepHours ?? null,
    restingHeartRate: data.restingHeartRate ?? null,
    hrv: data.hrv ?? null,
    fatigueScore: data.fatigueScore ?? 3,
    sessionSport: typeof data.sessionSport === 'string' ? data.sessionSport : null,
    sessionSportGroup:
      typeof data.sessionSportGroup === 'string' ? data.sessionSportGroup : null,
  };
}

/** Recent-first check-ins for the last `days` calendar days. */
export async function loadCheckIns(
  athleteUid: string,
  days = 35,
): Promise<DailyEntry[]> {
  const db = getFirestore();
  const since = Timestamp.fromDate(new Date(Date.now() - days * 24 * 60 * 60 * 1000));
  const snap = await db
    .collection('athletes')
    .doc(athleteUid)
    .collection('checkins')
    .where('date', '>=', since)
    .orderBy('date', 'desc')
    .get();
  return snap.docs.map((d) => entryFromCheckInDoc(d.id, d.data()));
}

export type CheckInLoader = (athleteUid: string, days: number) => Promise<DailyEntry[]>;
