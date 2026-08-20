/**
 * Nightly alerts — risk spike, missed check-in (2+ days), device sync
 * failure. Writes athletes/{uid}/alerts and coaches/{coachUid}/alerts
 * (admin SDK; clients are read-only per firestore.rules). Then FCM-pushes
 * stored tokens on users/{uid}.
 */

import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';

const RISK_RANK: Record<string, number> = { LOW: 0, MEDIUM: 1, HIGH: 2 };

export interface NightlyAlertStats {
  riskSpikes: number;
  missedCheckIns: number;
  syncFailures: number;
  pushes: number;
}

function todayKey(now = new Date()): string {
  return now.toISOString().slice(0, 10);
}

function riskRank(level: string | null | undefined): number {
  if (!level) return -1;
  return RISK_RANK[level.toUpperCase()] ?? -1;
}

function twoDaysMs(): number {
  return 2 * 24 * 60 * 60 * 1000;
}

async function sendPush(
  uid: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<boolean> {
  const db = getFirestore();
  const userSnap = await db.collection('users').doc(uid).get();
  const token = userSnap.data()?.fcmToken;
  if (typeof token !== 'string' || !token.trim()) return false;

  try {
    await getMessaging().send({
      token: token.trim(),
      notification: { title, body },
      data,
    });
    return true;
  } catch (err) {
    const code = (err as { code?: string }).code ?? '';
    logger.warn(`FCM send failed for ${uid}`, err);
    if (
      code.includes('registration-token-not-registered') ||
      code.includes('invalid-registration-token') ||
      code.includes('messaging/registration-token-not-registered')
    ) {
      await db.collection('users').doc(uid).update({ fcmToken: null });
    }
    return false;
  }
}

async function writeAthleteAlert(
  athleteUid: string,
  docId: string,
  payload: {
    title: string;
    type: string;
    timestamp: string;
  },
): Promise<void> {
  const db = getFirestore();
  await db
    .collection('athletes')
    .doc(athleteUid)
    .collection('alerts')
    .doc(docId)
    .set(
      {
        ...payload,
        timeAgo: 'Just now',
        read: false,
      },
      { merge: true },
    );
}

async function writeCoachAlert(
  coachUid: string,
  docId: string,
  payload: {
    type: string;
    urgency: string;
    athleteUid: string;
    athleteName: string;
    title: string;
    summary: string;
    timestamp: string;
  },
): Promise<void> {
  const db = getFirestore();
  await db
    .collection('coaches')
    .doc(coachUid)
    .collection('alerts')
    .doc(docId)
    .set({ ...payload, read: false }, { merge: true });
}

async function lastCheckInAt(athleteUid: string): Promise<Date | null> {
  const db = getFirestore();
  const snap = await db
    .collection('athletes')
    .doc(athleteUid)
    .collection('checkins')
    .orderBy('date', 'desc')
    .limit(1)
    .get();
  if (snap.empty) return null;
  const raw = snap.docs[0].data().date;
  if (raw && typeof raw.toDate === 'function') return raw.toDate() as Date;
  if (typeof raw === 'string') {
    const parsed = new Date(raw);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

async function hasStaleOrFailedSync(athleteUid: string): Promise<string | null> {
  const db = getFirestore();
  const snap = await db
    .collection('athletes')
    .doc(athleteUid)
    .collection('devices')
    .get();

  const cutoff = Date.now() - twoDaysMs();
  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.connected === false) continue;
    if (
      doc.id === 'manual_tier3' ||
      data.requiresWearableSync === false ||
      String(data.name ?? '').trim().toLowerCase() === 'manual entry'
    ) {
      continue;
    }

    const err = typeof data.lastSyncError === 'string' ? data.lastSyncError.trim() : '';
    if (err) {
      return err;
    }

    const lastSyncRaw = data.lastSync as string | undefined;
    if (!lastSyncRaw) {
      return `${doc.id} has never completed a sync.`;
    }
    const lastSync = Date.parse(lastSyncRaw);
    if (Number.isNaN(lastSync) || lastSync < cutoff) {
      return `${doc.id} last synced more than 2 days ago.`;
    }
  }
  return null;
}

export async function evaluateNightlyAlerts(opts: {
  athleteUid: string;
  athleteName: string;
  coachUid: string | null;
  previousRiskLevel: string | null;
  newRiskLevel: string | null;
  createdAt?: string | null;
}): Promise<NightlyAlertStats> {
  const stats: NightlyAlertStats = {
    riskSpikes: 0,
    missedCheckIns: 0,
    syncFailures: 0,
    pushes: 0,
  };
  const now = new Date();
  const day = todayKey(now);
  const timestamp = now.toISOString();
  const { athleteUid, athleteName, coachUid } = opts;

  const notify = async (
    title: string,
    body: string,
    type: string,
    alsoCoach: boolean,
  ) => {
    if (await sendPush(athleteUid, title, body, { type, athleteUid })) {
      stats.pushes++;
    }
    if (alsoCoach && coachUid) {
      if (
        await sendPush(coachUid, title, body, {
          type,
          athleteUid,
          athleteName,
        })
      ) {
        stats.pushes++;
      }
    }
  };

  // --- Risk spike: tier increased vs yesterday's stored level ---
  if (riskRank(opts.newRiskLevel) > riskRank(opts.previousRiskLevel)) {
    const title = `${athleteName}'s injury risk rose to ${opts.newRiskLevel}`;
    const type = 'risk_spike';
    await writeAthleteAlert(athleteUid, `risk-spike-${day}`, {
      title,
      type,
      timestamp,
    });
    if (coachUid) {
      await writeCoachAlert(coachUid, `risk-spike-${athleteUid}-${day}`, {
        type,
        urgency: opts.newRiskLevel ?? 'HIGH',
        athleteUid,
        athleteName,
        title,
        summary: `${opts.previousRiskLevel ?? 'none'} → ${opts.newRiskLevel}`,
        timestamp,
      });
    }
    await notify(title, 'Review the new recommendation in AthleteIQ.', type, true);
    stats.riskSpikes++;
  }

  // --- Missed check-in: 2+ days since last log ---
  const createdMs = opts.createdAt ? Date.parse(opts.createdAt) : NaN;
  const athleteIsNew =
    !Number.isNaN(createdMs) && Date.now() - createdMs < twoDaysMs();
  if (!athleteIsNew) {
    const last = await lastCheckInAt(athleteUid);
    const stale = !last || Date.now() - last.getTime() >= twoDaysMs();
    if (stale) {
      const title = last
        ? `No check-in for 2+ days`
        : `Don't forget to log today's training`;
      const type = 'missed_checkin';
      await writeAthleteAlert(athleteUid, `missed-checkin-${day}`, {
        title,
        type,
        timestamp,
      });
      if (coachUid) {
        await writeCoachAlert(coachUid, `missed-checkin-${athleteUid}-${day}`, {
          type,
          urgency: 'MEDIUM',
          athleteUid,
          athleteName,
          title: `${athleteName} missed check-ins`,
          summary: last
            ? `Last log ${last.toISOString().slice(0, 10)}`
            : 'No check-ins on file',
          timestamp,
        });
      }
      await notify(
        title,
        'Open AthleteIQ and log fatigue, sleep, and training.',
        type,
        true,
      );
      stats.missedCheckIns++;
    }
  }

  // --- Wearable sync failure / stale lastSync ---
  const syncIssue = await hasStaleOrFailedSync(athleteUid);
  if (syncIssue) {
    const title = 'Wearable sync needs attention';
    const type = 'sync_failure';
    await writeAthleteAlert(athleteUid, `sync-fail-${day}`, {
      title,
      type,
      timestamp,
    });
    if (coachUid) {
      await writeCoachAlert(coachUid, `sync-fail-${athleteUid}-${day}`, {
        type,
        urgency: 'MEDIUM',
        athleteUid,
        athleteName,
        title: `${athleteName}: device sync failed`,
        summary: syncIssue,
        timestamp,
      });
    }
    await notify(title, syncIssue, type, true);
    stats.syncFailures++;
  }

  return stats;
}
