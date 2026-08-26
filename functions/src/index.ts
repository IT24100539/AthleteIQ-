import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onDocumentUpdated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { defineSecret } from 'firebase-functions/params';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { runRiskPipeline } from './riskPipeline';
import { answerAthleteQuestion } from './aiChat';
import { parseAthleteSports } from './athleteSports';
import { classifyCustomSport as classifySportText } from './sportClassifier';
import { classifyPainUrgency } from './painUrgency';
import { buildWeeklyReport, redactWeeklyReportForCoach } from './weeklyReport';
import { parsePrivacySettings } from './privacySettings';
import { evaluateNightlyAlerts, NightlyAlertStats } from './nightlyAlerts';
import { deleteAccountForUid } from './deleteAccount';
import {
  applyHumanReview,
  evaluateAthleteHistory,
  evaluateStoredOutput,
  parseKinds,
} from './evaluation/evaluate';
import { isPromptKind } from './evaluation/rubric';
import {
  privacySettingsChanged,
  resyncAllCheckInCoachViews,
  writeAthleteRiskView,
  writeCheckInCoachView,
} from './privacyViews';
import { athleteAccessDecision } from './athleteAccess';
import {
  notifyAthleteRecommendationReleased,
  shouldNotifyRecommendationRelease,
} from './recommendationNotify';

initializeApp();
const db = getFirestore();

/** Bound onto every function that calls ChatAnthropic. Without this,
 *  `firebase functions:secrets:set` creates the secret but process.env
 *  stays empty in production. */
const anthropicApiKey = defineSecret('ANTHROPIC_API_KEY');

async function requireAthleteOrCoach(
  request: CallableRequest,
): Promise<{ athleteUid: string; isCoach: boolean }> {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }

  const athleteUid: string | undefined = request.data?.athleteUid;
  if (!athleteUid) {
    throw new HttpsError('invalid-argument', 'athleteUid is required.');
  }

  const athleteDoc = await db.collection('athletes').doc(athleteUid).get();
  if (!athleteDoc.exists) {
    throw new HttpsError('not-found', 'Athlete profile not found.');
  }
  const athleteData = athleteDoc.data()!;
  const decision = athleteAccessDecision({
    callerUid: request.auth.uid,
    athleteUid,
    coachUid: typeof athleteData.coachUid === 'string' ? athleteData.coachUid : null,
  });
  if (decision === 'denied') {
    throw new HttpsError('permission-denied', 'Not authorized for this athlete.');
  }
  return { athleteUid, isCoach: decision === 'coach' };
}

/** Athlete onboarding — only the signed-in athlete may classify their sport. */
async function requireSelfAthlete(request: CallableRequest): Promise<{ athleteUid: string }> {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }
  const athleteUid: string | undefined = request.data?.athleteUid;
  if (!athleteUid) {
    throw new HttpsError('invalid-argument', 'athleteUid is required.');
  }
  if (request.auth.uid !== athleteUid) {
    throw new HttpsError('permission-denied', 'Only the athlete may set their sport.');
  }
  const athleteDoc = await db.collection('athletes').doc(athleteUid).get();
  if (!athleteDoc.exists) {
    throw new HttpsError('not-found', 'Athlete profile not found.');
  }
  return { athleteUid };
}

/**
 * On-demand callable — Flutter calls this after a check-in.
 * Auth: athlete themself or their assigned coach.
 */
export const recalculateRisk = onCall(
  {
    timeoutSeconds: 120,
    memory: '512MiB',
    secrets: [anthropicApiKey],
  },
  async (request) => {
    const { athleteUid } = await requireAthleteOrCoach(request);

    const result = await runRiskPipeline(athleteUid);
    if (result.status === 'not_found') {
      throw new HttpsError('not-found', 'Athlete profile not found.');
    }
    return result;
  },
);

/**
 * Nightly job — same pipeline as recalculateRisk, then alert checks
 * (risk spike vs yesterday, missed check-ins, sync failures) + FCM.
 * Athletes with fewer than 5 check-ins in the 35-day window are marked
 * insufficientData (no risk write). Runs 03:00 UTC.
 */
export const nightlyRecalculateRisk = onSchedule(
  {
    schedule: '0 3 * * *',
    timeZone: 'UTC',
    timeoutSeconds: 540,
    memory: '512MiB',
    secrets: [anthropicApiKey],
  },
  async () => {
    const athletes = await db.collection('athletes').get();
    let ok = 0;
    let skipped = 0;
    let failed = 0;
    const alerts: NightlyAlertStats = {
      riskSpikes: 0,
      missedCheckIns: 0,
      syncFailures: 0,
      pushes: 0,
    };

    for (const doc of athletes.docs) {
      try {
        const latestSnap = await db
          .collection('athletes')
          .doc(doc.id)
          .collection('riskResults')
          .doc('latest')
          .get();
        const previousRiskLevel =
          typeof latestSnap.data()?.riskLevel === 'string'
            ? (latestSnap.data()!.riskLevel as string)
            : null;

        const result = await runRiskPipeline(doc.id);
        // Backfill checkinsCoachView for rosters that predate the
        // filtered-view triggers (fail-closed until this runs).
        await resyncAllCheckInCoachViews(doc.id);
        if (result.status === 'ok') {
          ok++;
        } else {
          skipped++;
        }

        const afterSnap = await db
          .collection('athletes')
          .doc(doc.id)
          .collection('riskResults')
          .doc('latest')
          .get();
        const newRiskLevel =
          result.status === 'ok' && typeof afterSnap.data()?.riskLevel === 'string'
            ? (afterSnap.data()!.riskLevel as string)
            : previousRiskLevel;

        const data = doc.data();
        const alertStats = await evaluateNightlyAlerts({
          athleteUid: doc.id,
          athleteName: String(data.name ?? 'Athlete'),
          coachUid: typeof data.coachUid === 'string' ? data.coachUid : null,
          previousRiskLevel,
          newRiskLevel,
          createdAt: typeof data.createdAt === 'string' ? data.createdAt : null,
        });
        alerts.riskSpikes += alertStats.riskSpikes;
        alerts.missedCheckIns += alertStats.missedCheckIns;
        alerts.syncFailures += alertStats.syncFailures;
        alerts.pushes += alertStats.pushes;
      } catch (err) {
        failed++;
        logger.error(`nightlyRecalculateRisk failed for ${doc.id}`, err);
      }
    }

    logger.info('nightlyRecalculateRisk finished', {
      athletes: athletes.size,
      ok,
      skipped,
      failed,
      ...alerts,
    });
  },
);

/**
 * Ask AthleteIQ — LangChain answer grounded in this athlete's last 14 days
 * of check-ins and latest riskResults. Auth: athlete or their coach.
 */
export const askAthleteIQ = onCall(
  {
    timeoutSeconds: 120,
    memory: '512MiB',
    secrets: [anthropicApiKey],
  },
  async (request) => {
    const { athleteUid } = await requireAthleteOrCoach(request);
    const question = String(request.data?.question ?? '').trim();
    if (!question) {
      throw new HttpsError('invalid-argument', 'question is required.');
    }

    const token = request.auth!.token;
    const callerName =
      (typeof token.name === 'string' && token.name) ||
      (typeof token.email === 'string' && token.email) ||
      'User';

    try {
      const answer = await answerAthleteQuestion({
        athleteUid,
        question,
        callerUid: request.auth!.uid,
        callerName,
      });
      return { text: answer.text, source: answer.source };
    } catch (err) {
      logger.error('askAthleteIQ failed', err);
      throw new HttpsError('internal', 'Could not answer that question.');
    }
  },
);

/**
 * Classify a free-text "Other" sport into the nearest sport group (Section 12.2).
 * Stores original text + classified group on the athlete profile.
 */
export const classifyCustomSport = onCall(
  {
    timeoutSeconds: 60,
    memory: '512MiB',
    secrets: [anthropicApiKey],
  },
  async (request) => {
    const { athleteUid } = await requireSelfAthlete(request);
    const sportText = String(request.data?.sportText ?? '').trim();
    if (!sportText) {
      throw new HttpsError('invalid-argument', 'sportText is required.');
    }

    const classification = await classifySportText(sportText);
    const persist = request.data?.persist !== false;

    if (persist) {
      const athleteRef = db.collection('athletes').doc(athleteUid);
      const snap = await athleteRef.get();
      const existing = parseAthleteSports(snap.data());
      const sports = [...existing.sports];
      const sportGroups = [...existing.sportGroups];
      const already = sports.findIndex(
        (s) => s.toLowerCase() === classification.sport.toLowerCase(),
      );
      if (already >= 0) {
        sportGroups[already] = classification.sportGroup;
      } else {
        sports.push(classification.sport);
        sportGroups.push(classification.sportGroup);
      }
      await athleteRef.update({
        sports,
        sportGroups,
        sport: sports[0] ?? classification.sport,
        sportGroup: sportGroups[0] ?? classification.sportGroup,
        sportClassificationConfidence: classification.confidence,
        sportClassificationSource: classification.source,
      });
    }

    return {
      sport: classification.sport,
      sportGroup: classification.sportGroup,
      groupLabel: classification.groupLabel,
      confidence: classification.confidence,
      source: classification.source,
    };
  },
);

/**
 * Athlete pain report — stores areas + notes, then LLM-triages urgency.
 * HIGH reports also write a coach alert. Triage aid, not a diagnosis.
 */
export const submitPainReport = onCall(
  {
    timeoutSeconds: 60,
    memory: '512MiB',
    secrets: [anthropicApiKey],
  },
  async (request) => {
    const { athleteUid } = await requireSelfAthlete(request);
    const rawAreas = request.data?.areas;
    if (!Array.isArray(rawAreas) || rawAreas.length === 0) {
      throw new HttpsError('invalid-argument', 'At least one body area is required.');
    }

    const areas = rawAreas
      .map((a: { location?: unknown; severity?: unknown }) => ({
        location: String(a?.location ?? '').trim(),
        severity: Math.min(5, Math.max(1, Number(a?.severity) || 1)),
      }))
      .filter((a: { location: string }) => a.location.length > 0);

    if (areas.length === 0) {
      throw new HttpsError('invalid-argument', 'At least one body area is required.');
    }

    const note = String(request.data?.note ?? '').trim();
    const triage = await classifyPainUrgency(note, areas);

    const athleteRef = db.collection('athletes').doc(athleteUid);
    const athleteSnap = await athleteRef.get();
    const athleteData = athleteSnap.data() ?? {};
    const athleteName = String(athleteData.name ?? 'Athlete');
    const coachUid =
      typeof athleteData.coachUid === 'string' ? athleteData.coachUid : null;

    const now = new Date();
    const summary = areas.map((a) => `${a.location} (${a.severity}/5)`).join(', ');

    // Admin SDK — firestore.rules deny client create on painReports and
    // client writes to latestPain*. These two writes are the only path.
    const reportRef = await athleteRef.collection('painReports').add({
      athleteUid,
      date: now.toISOString(),
      areas,
      note: note || null,
      urgency: triage.urgency,
      urgencyReason: triage.reason,
      urgencySource: triage.source,
    });

    await athleteRef.update({
      latestPainUrgency: triage.urgency,
      latestPainAt: now.toISOString(),
      latestPainSummary: summary,
      latestPainReportId: reportRef.id,
    });

    if (triage.urgency === 'HIGH' && coachUid) {
      await db.collection('coaches').doc(coachUid).collection('alerts').add({
        type: 'pain',
        urgency: 'HIGH',
        athleteUid,
        athleteName,
        title: `HIGH pain report — ${athleteName}`,
        summary,
        reportId: reportRef.id,
        timestamp: now.toISOString(),
        read: false,
      });
    }

    return {
      reportId: reportRef.id,
      urgency: triage.urgency,
      urgencyReason: triage.reason,
      urgencySource: triage.source,
    };
  },
);

/**
 * Keep riskResults/athleteView in sync when the coach approves/modifies
 * `latest` from the client. Pipeline writes also call writeAthleteRiskView
 * directly; this trigger covers the Human Approval Step path.
 */
export const onRiskLatestWritten = onDocumentWritten(
  'athletes/{athleteUid}/riskResults/latest',
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    const afterData = after?.exists ? after.data() : undefined;
    await writeAthleteRiskView(event.params.athleteUid, afterData);

    const beforeData = before?.exists ? before.data() : undefined;
    if (
      afterData &&
      shouldNotifyRecommendationRelease(beforeData, afterData)
    ) {
      await notifyAthleteRecommendationReleased(
        event.params.athleteUid,
        afterData,
      );
    }
  },
);

/**
 * Raw checkins/ stay athlete-only. This writes the privacy-filtered
 * checkinsCoachView/{id} the assigned coach is allowed to read.
 */
export const onCheckInWritten = onDocumentWritten(
  'athletes/{athleteUid}/checkins/{checkinId}',
  async (event) => {
    const { athleteUid, checkinId } = event.params;
    const after = event.data?.after;
    const athleteSnap = await db.collection('athletes').doc(athleteUid).get();
    const privacy = parsePrivacySettings(athleteSnap.data()?.privacySettings);
    await writeCheckInCoachView(
      athleteUid,
      checkinId,
      after?.exists ? after.data() : undefined,
      privacy,
    );
  },
);

/** Re-filter every coach view when the athlete flips a sharing toggle. */
export const onAthletePrivacyUpdated = onDocumentUpdated(
  'athletes/{athleteUid}',
  async (event) => {
    const before = event.data?.before.data()?.privacySettings;
    const after = event.data?.after.data()?.privacySettings;
    if (!privacySettingsChanged(before, after)) return;
    logger.info('privacySettings changed; resyncing checkinsCoachView', {
      athleteUid: event.params.athleteUid,
    });
    await resyncAllCheckInCoachViews(event.params.athleteUid);
  },
);

/**
 * One-shot backfill of checkinsCoachView for an athlete. Auth: that athlete
 * or their assigned coach. Nightly also runs this; this callable is for
 * deploy-day catch-up without waiting until 03:00 UTC.
 */
export const resyncCheckInCoachViews = onCall(
  {
    timeoutSeconds: 120,
    memory: '256MiB',
  },
  async (request) => {
    const { athleteUid } = await requireAthleteOrCoach(request);
    const written = await resyncAllCheckInCoachViews(athleteUid);
    logger.info('resyncCheckInCoachViews finished', { athleteUid, written });
    return { status: 'ok', written };
  },
);

/**
 * Apple / Google require a real delete-account path for health apps.
 * Wipes Auth + Firestore for the signed-in caller only. Coaches unlink
 * roster athletes instead of deleting them.
 */
export const deleteAccount = onCall(
  {
    timeoutSeconds: 120,
    memory: '512MiB',
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in required.');
    }
    const confirm = String(request.data?.confirm ?? '').trim();
    if (confirm !== 'DELETE') {
      throw new HttpsError(
        'invalid-argument',
        'Type DELETE to confirm account deletion.',
      );
    }
    return deleteAccountForUid(request.auth.uid);
  },
);

/**
 * Week in review — structured stats from check-ins + grounded LLM narrative.
 * Auth: athlete or their coach.
 */
export const getWeeklyReport = onCall(
  {
    timeoutSeconds: 60,
    memory: '512MiB',
    secrets: [anthropicApiKey],
  },
  async (request) => {
    const { athleteUid, isCoach } = await requireAthleteOrCoach(request);
    const weekOffset = Number(request.data?.weekOffset ?? 0);
    if (!Number.isFinite(weekOffset)) {
      throw new HttpsError('invalid-argument', 'weekOffset must be a number.');
    }

    try {
      const report = await buildWeeklyReport(athleteUid, Math.trunc(weekOffset));
      if (!isCoach) return report;
      const athleteSnap = await db.collection('athletes').doc(athleteUid).get();
      const privacy = parsePrivacySettings(athleteSnap.data()?.privacySettings);
      return redactWeeklyReportForCoach(report, privacy);
    } catch (err) {
      logger.error('getWeeklyReport failed', err);
      throw new HttpsError('internal', 'Could not build weekly report.');
    }
  },
);

/**
 * Manual LLM-as-judge. Scores one stored output for this athlete against
 * the rubric for `kind`. Does not run on the live generation path.
 * Auth: athlete or their assigned coach.
 */
export const evaluateLlmOutput = onCall(
  {
    timeoutSeconds: 120,
    memory: '512MiB',
    secrets: [anthropicApiKey],
    invoker: 'public',
  },
  async (request) => {
    const { athleteUid } = await requireAthleteOrCoach(request);
    const kind = request.data?.kind;
    if (!isPromptKind(kind)) {
      throw new HttpsError(
        'invalid-argument',
        'kind must be one of askAthleteIQ, orchestrator, graded, explain, research, triage, classify, weekly.',
      );
    }
    try {
      return await evaluateStoredOutput({ athleteUid, kind });
    } catch (err) {
      logger.error('evaluateLlmOutput failed', err);
      throw new HttpsError('internal', 'Could not evaluate that output.');
    }
  },
);

/**
 * Manual batch judge over stored history (default: first-pass kinds).
 * Not scheduled. Auth: athlete or their assigned coach.
 */
export const evaluateAthleteLlmHistory = onCall(
  {
    timeoutSeconds: 180,
    memory: '512MiB',
    secrets: [anthropicApiKey],
    invoker: 'public',
  },
  async (request) => {
    const { athleteUid } = await requireAthleteOrCoach(request);
    const kinds = parseKinds(request.data?.kinds);
    try {
      return await evaluateAthleteHistory({ athleteUid, kinds });
    } catch (err) {
      logger.error('evaluateAthleteLlmHistory failed', err);
      throw new HttpsError('internal', 'Could not evaluate stored outputs.');
    }
  },
);

/**
 * Human spot-check of a stored judge record. Flags agreement / disagreement
 * so verbosity and leniency bias can be caught without re-running Claude.
 */
export const reviewLlmEvaluation = onCall(
  {
    timeoutSeconds: 30,
    memory: '256MiB',
    invoker: 'public',
  },
  async (request) => {
    const { athleteUid } = await requireAthleteOrCoach(request);
    const evalId = String(request.data?.evalId ?? '').trim();
    if (!evalId) {
      throw new HttpsError('invalid-argument', 'evalId is required.');
    }
    const agreement = String(request.data?.agreement ?? '').trim();
    if (agreement !== 'agree' && agreement !== 'disagree') {
      throw new HttpsError('invalid-argument', 'agreement must be agree or disagree.');
    }
    const rawIds = request.data?.disagreedItemIds;
    const disagreedItemIds = Array.isArray(rawIds)
      ? rawIds.map((id: unknown) => String(id)).filter(Boolean)
      : [];
    try {
      const humanReview = await applyHumanReview({
        athleteUid,
        evalId,
        reviewerUid: request.auth!.uid,
        agreement,
        disagreedItemIds,
        note: String(request.data?.note ?? ''),
      });
      return { evalId, humanReview };
    } catch (err) {
      logger.error('reviewLlmEvaluation failed', err);
      throw new HttpsError('not-found', 'Evaluation not found.');
    }
  },
);
