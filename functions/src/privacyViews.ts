/**
 * Server-side filtered views. Firestore rules are document-level, so
 * pending recommendations and per-toggle check-in fields cannot be
 * hidden inside a mixed document. These helpers write the only copies
 * clients are allowed to read for those cases.
 */

import { DocumentData, getFirestore } from 'firebase-admin/firestore';
import { parsePrivacySettings, PrivacySettings } from './privacySettings';

export const ATHLETE_VIEW_ID = 'athleteView';
export const CHECKINS_COACH_VIEW = 'checkinsCoachView';

export function isRecommendationReleased(status: unknown): boolean {
  const s = typeof status === 'string' ? status.toLowerCase() : 'pending';
  return s === 'approved' || s === 'modified';
}

/**
 * Scores are OK to show a pending-status athlete. Recommendation prose,
 * graded options, LLM / research text, and orchestrator internals are not.
 * After approve/modify, the released plan is copied in; coach-only
 * internals stay on `latest`.
 */
export function buildAthleteRiskView(latest: DocumentData): DocumentData {
  if (latest.insufficientData === true) {
    return {
      kind: ATHLETE_VIEW_ID,
      insufficientData: true,
      checkInCount: latest.checkInCount ?? 0,
      recommendationStatus: latest.recommendationStatus ?? 'pending',
    };
  }

  const view: DocumentData = {
    kind: ATHLETE_VIEW_ID,
    insufficientData: false,
    riskLevel: latest.riskLevel ?? 'LOW',
    confidence: latest.confidence ?? '',
    acwr: latest.acwr ?? 0,
    trainingLoad7d: latest.trainingLoad7d ?? 0,
    trainingLoad28dAvg: latest.trainingLoad28dAvg ?? 0,
    recoveryTrend: latest.recoveryTrend ?? 'stable',
    performancePrediction: latest.performancePrediction ?? 'AVERAGE',
    recommendationStatus: latest.recommendationStatus ?? 'pending',
    calculatedAt: latest.calculatedAt ?? new Date().toISOString(),
    fatiguePersistent: latest.fatiguePersistent === true,
  };

  if (latest.performanceFrame != null) {
    view.performanceFrame = latest.performanceFrame;
  }
  if (latest.performanceFrameAxis != null) {
    view.performanceFrameAxis = latest.performanceFrameAxis;
  }
  if (latest.riskLevelPatternFlag != null) {
    view.riskLevelPatternFlag = latest.riskLevelPatternFlag;
  }
  if (latest.avgFatigue7d != null) {
    view.avgFatigue7d = latest.avgFatigue7d;
  }

  if (isRecommendationReleased(latest.recommendationStatus)) {
    view.recommendation = latest.recommendation ?? '';
    view.reason = latest.reason ?? '';
    if (Array.isArray(latest.gradedOptions)) {
      view.gradedOptions = latest.gradedOptions;
    }
  }

  return view;
}

/** Copy only the check-in keys the athlete has shared with their coach. */
export function buildCheckInCoachView(
  data: DocumentData,
  privacy: PrivacySettings,
): DocumentData {
  const view: DocumentData = {
    date: data.date,
    source: data.source ?? 'manual',
  };

  if (typeof data.sessionSport === 'string') {
    view.sessionSport = data.sessionSport;
  }
  if (typeof data.sessionSportGroup === 'string') {
    view.sessionSportGroup = data.sessionSportGroup;
  }

  if (privacy.trainingLogs) {
    if (data.sessionDurationMinutes != null) {
      view.sessionDurationMinutes = data.sessionDurationMinutes;
    }
    if (data.rpe != null) {
      view.rpe = data.rpe;
    }
  }

  if (privacy.dailyFatigueCheckIn && data.fatigueScore != null) {
    view.fatigueScore = data.fatigueScore;
  }

  if (privacy.wearableData) {
    if (data.sleepHours != null) view.sleepHours = data.sleepHours;
    if (data.restingHeartRate != null) {
      view.restingHeartRate = data.restingHeartRate;
    }
    if (data.hrv != null) view.hrv = data.hrv;
  }

  if (privacy.injuryHistory && data.soreness != null) {
    view.soreness = data.soreness;
  }

  return view;
}

export async function writeAthleteRiskView(
  athleteUid: string,
  latest: DocumentData | undefined,
): Promise<void> {
  const ref = getFirestore()
    .collection('athletes')
    .doc(athleteUid)
    .collection('riskResults')
    .doc(ATHLETE_VIEW_ID);
  if (!latest) {
    await ref.delete();
    return;
  }
  // Replace, never merge — a pending rewrite must drop a prior recommendation.
  await ref.set(buildAthleteRiskView(latest));
}

export async function writeCheckInCoachView(
  athleteUid: string,
  checkinId: string,
  data: DocumentData | undefined,
  privacy: PrivacySettings,
): Promise<void> {
  const ref = getFirestore()
    .collection('athletes')
    .doc(athleteUid)
    .collection(CHECKINS_COACH_VIEW)
    .doc(checkinId);
  if (!data) {
    await ref.delete();
    return;
  }
  await ref.set(buildCheckInCoachView(data, privacy));
}

export async function resyncAllCheckInCoachViews(
  athleteUid: string,
): Promise<number> {
  const db = getFirestore();
  const athleteSnap = await db.collection('athletes').doc(athleteUid).get();
  const privacy = parsePrivacySettings(athleteSnap.data()?.privacySettings);
  const checkins = await db
    .collection('athletes')
    .doc(athleteUid)
    .collection('checkins')
    .get();

  const viewCol = db
    .collection('athletes')
    .doc(athleteUid)
    .collection(CHECKINS_COACH_VIEW);

  let batch = db.batch();
  let count = 0;
  for (const doc of checkins.docs) {
    batch.set(viewCol.doc(doc.id), buildCheckInCoachView(doc.data(), privacy));
    count++;
    if (count === 400) {
      await batch.commit();
      batch = db.batch();
      count = 0;
    }
  }
  if (count > 0) {
    await batch.commit();
  }
  return checkins.size;
}

export function privacySettingsChanged(
  before: unknown,
  after: unknown,
): boolean {
  return JSON.stringify(before ?? {}) !== JSON.stringify(after ?? {});
}
