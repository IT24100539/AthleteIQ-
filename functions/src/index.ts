import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { DailyEntry } from './calculations';
import { assessRisk } from './riskModel';
import { buildRecommendation, SportGroup } from './recommendationEngine';

initializeApp();
const db = getFirestore();

/**
 * The whole pipeline in one place, matching Section 13.3: one shared
 * set of signals, read by both the Risk Model and Performance Model,
 * then handed to the Orchestrator (Section 6) to produce one
 * recommendation. Called by the client right after a check-in is
 * written (see FirestoreService.submitCheckIn in the Flutter app).
 */
export const recalculateRisk = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }

  const athleteUid: string | undefined = request.data?.athleteUid;
  if (!athleteUid) {
    throw new HttpsError('invalid-argument', 'athleteUid is required.');
  }

  // Only the athlete themself, or their assigned coach, may trigger this.
  const athleteDoc = await db.collection('athletes').doc(athleteUid).get();
  if (!athleteDoc.exists) {
    throw new HttpsError('not-found', 'Athlete profile not found.');
  }
  const athleteData = athleteDoc.data()!;
  const isSelf = request.auth.uid === athleteUid;
  const isCoach = request.auth.uid === athleteData.coachUid;
  if (!isSelf && !isCoach) {
    throw new HttpsError('permission-denied', 'Not authorized for this athlete.');
  }

  // Pull the last 35 days of check-ins, newest first.
  const since = Timestamp.fromDate(new Date(Date.now() - 35 * 24 * 60 * 60 * 1000));
  const snap = await db
    .collection('athletes')
    .doc(athleteUid)
    .collection('checkins')
    .where('date', '>=', since)
    .orderBy('date', 'desc')
    .get();

  const entries: DailyEntry[] = snap.docs.map((d) => {
    const data = d.data();
    const durationMin = data.sessionDurationMinutes ?? null;
    const rpe = data.rpe ?? null;
    return {
      date: d.id,
      trainingLoad: durationMin !== null && rpe !== null ? durationMin * rpe : null,
      sleepHours: data.sleepHours ?? null,
      restingHeartRate: data.restingHeartRate ?? null,
      hrv: data.hrv ?? null,
      fatigueScore: data.fatigueScore ?? 3,
    };
  });

  if (entries.length < 5) {
    // Section — "Not enough data" empty state. Don't fabricate a score.
    await db
      .collection('athletes')
      .doc(athleteUid)
      .collection('riskResults')
      .doc('latest')
      .set({ insufficientData: true, checkInCount: entries.length }, { merge: true });
    return { status: 'insufficient_data', checkInCount: entries.length };
  }

  const assessment = assessRisk(entries);
  const sportGroup = (athleteData.sportGroup ?? 'other') as SportGroup;
  const recommendation = buildRecommendation(
    assessment.riskLevel,
    assessment.performancePrediction,
    sportGroup,
  );

  // Human Approval Step (Section 6 / 11): every new calculation resets
  // to 'pending' — nothing reaches the athlete until the coach reviews it.
  await db
    .collection('athletes')
    .doc(athleteUid)
    .collection('riskResults')
    .doc('latest')
    .set({
      riskLevel: assessment.riskLevel,
      confidence: assessment.confidence,
      reason: `${assessment.reason} ${recommendation.orchestratorNote}`,
      acwr: assessment.acwr,
      trainingLoad7d: assessment.trainingLoad7d,
      trainingLoad28dAvg: assessment.trainingLoad28dAvg,
      recoveryTrend: assessment.recoveryTrend,
      performancePrediction: assessment.performancePrediction,
      recommendation: recommendation.action,
      recommendationStatus: 'pending',
      insufficientData: false,
      calculatedAt: new Date().toISOString(),
    });

  return { status: 'ok', riskLevel: assessment.riskLevel };
});
