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

export type NightlyAlertType = 'risk_spike' | 'missed_checkin' | 'sync_failure';

export interface PlannedAthleteAlert {
  recipient: 'athlete';
  athleteUid: string;
  docId: string;
  type: NightlyAlertType;
  title: string;
  timestamp: string;
}

export interface PlannedCoachAlert {
  recipient: 'coach';
  coachUid: string;
  athleteUid: string;
  athleteName: string;
  docId: string;
  type: NightlyAlertType;
  urgency: string;
  title: string;
  summary: string;
  timestamp: string;
}

export interface NightlyAlertPlan {
  athleteAlerts: PlannedAthleteAlert[];
  coachAlerts: PlannedCoachAlert[];
  riskSpikes: number;
  missedCheckIns: number;
  syncFailures: number;
}

export interface DeviceSyncRecord {
  id: string;
  connected?: boolean;
  requiresWearableSync?: boolean;
  name?: string;
  lastSyncError?: string;
  lastSync?: string;
}

function todayKey(now = new Date()): string {
  return now.toISOString().slice(0, 10);
}

export function riskRank(level: string | null | undefined): number {
  if (!level) return -1;
  return RISK_RANK[level.toUpperCase()] ?? -1;
}

export function isRiskSpike(
  previousRiskLevel: string | null | undefined,
  newRiskLevel: string | null | undefined,
): boolean {
  return riskRank(newRiskLevel) > riskRank(previousRiskLevel);
}

export function twoDaysMs(): number {
  return 2 * 24 * 60 * 60 * 1000;
}

/** New profiles get a 2-day grace window before missed-check-in fires. */
export function isMissedCheckIn(opts: {
  lastCheckInAt: Date | null;
  now: Date;
  athleteCreatedAt: Date | null;
}): boolean {
  if (opts.athleteCreatedAt) {
    if (opts.now.getTime() - opts.athleteCreatedAt.getTime() < twoDaysMs()) {
      return false;
    }
  }
  const last = opts.lastCheckInAt;
  return !last || opts.now.getTime() - last.getTime() >= twoDaysMs();
}

export function syncIssueFromDevices(
  devices: DeviceSyncRecord[],
  now = new Date(),
): string | null {
  const cutoff = now.getTime() - twoDaysMs();
  for (const data of devices) {
    if (data.connected === false) continue;
    if (
      data.id === 'manual_tier3' ||
      data.requiresWearableSync === false ||
      String(data.name ?? '').trim().toLowerCase() === 'manual entry'
    ) {
      continue;
    }

    const err = typeof data.lastSyncError === 'string' ? data.lastSyncError.trim() : '';
    if (err) {
      return err;
    }

    const lastSyncRaw = data.lastSync;
    if (!lastSyncRaw) {
      return `${data.id} has never completed a sync.`;
    }
    const lastSync = Date.parse(lastSyncRaw);
    if (Number.isNaN(lastSync) || lastSync < cutoff) {
      return `${data.id} last synced more than 2 days ago.`;
    }
  }
  return null;
}

/**
 * Pure plan of which alert docs would be written and to whom.
 * evaluateNightlyAlerts executes this plan against Firestore.
 */
export function planNightlyAlerts(opts: {
  athleteUid: string;
  athleteName: string;
  coachUid: string | null;
  previousRiskLevel: string | null;
  newRiskLevel: string | null;
  lastCheckInAt: Date | null;
  athleteCreatedAt: Date | null;
  syncIssue: string | null;
  now?: Date;
}): NightlyAlertPlan {
  const now = opts.now ?? new Date();
  const day = todayKey(now);
  const timestamp = now.toISOString();
  const { athleteUid, athleteName, coachUid } = opts;

  const plan: NightlyAlertPlan = {
    athleteAlerts: [],
    coachAlerts: [],
    riskSpikes: 0,
    missedCheckIns: 0,
    syncFailures: 0,
  };

  const pushAthlete = (docId: string, type: NightlyAlertType, title: string) => {
    plan.athleteAlerts.push({
      recipient: 'athlete',
      athleteUid,
      docId,
      type,
      title,
      timestamp,
    });
  };

  const pushCoach = (
    docId: string,
    type: NightlyAlertType,
    urgency: string,
    title: string,
    summary: string,
  ) => {
    if (!coachUid) return;
    plan.coachAlerts.push({
      recipient: 'coach',
      coachUid,
      athleteUid,
      athleteName,
      docId,
      type,
      urgency,
      title,
      summary,
      timestamp,
    });
  };

  if (isRiskSpike(opts.previousRiskLevel, opts.newRiskLevel)) {
    const title = `${athleteName}'s injury risk rose to ${opts.newRiskLevel}`;
    const type: NightlyAlertType = 'risk_spike';
    pushAthlete(`risk-spike-${day}`, type, title);
    pushCoach(
      `risk-spike-${athleteUid}-${day}`,
      type,
      opts.newRiskLevel ?? 'HIGH',
      title,
      `${opts.previousRiskLevel ?? 'none'} → ${opts.newRiskLevel}`,
    );
    plan.riskSpikes++;
  }

  if (isMissedCheckIn({
    lastCheckInAt: opts.lastCheckInAt,
    now,
    athleteCreatedAt: opts.athleteCreatedAt,
  })) {
    const last = opts.lastCheckInAt;
    const title = last
      ? `No check-in for 2+ days`
      : `Don't forget to log today's training`;
    const type: NightlyAlertType = 'missed_checkin';
    pushAthlete(`missed-checkin-${day}`, type, title);
    pushCoach(
      `missed-checkin-${athleteUid}-${day}`,
      type,
      'MEDIUM',
      `${athleteName} missed check-ins`,
      last ? `Last log ${last.toISOString().slice(0, 10)}` : 'No check-ins on file',
    );
    plan.missedCheckIns++;
  }

  if (opts.syncIssue) {
    const type: NightlyAlertType = 'sync_failure';
    pushAthlete(`sync-fail-${day}`, type, 'Wearable sync needs attention');
    pushCoach(
      `sync-fail-${athleteUid}-${day}`,
      type,
      'MEDIUM',
      `${athleteName}: device sync failed`,
      opts.syncIssue,
    );
    plan.syncFailures++;
  }

  return plan;
}

export async function sendPushToUser(
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

  return syncIssueFromDevices(
    snap.docs.map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        connected: data.connected,
        requiresWearableSync: data.requiresWearableSync,
        name: data.name,
        lastSyncError: data.lastSyncError,
        lastSync: data.lastSync,
      };
    }),
  );
}

function parseCreatedAt(raw: string | null | undefined): Date | null {
  if (!raw) return null;
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
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
  const { athleteUid, athleteName, coachUid } = opts;
  const last = await lastCheckInAt(athleteUid);
  const syncIssue = await hasStaleOrFailedSync(athleteUid);
  const plan = planNightlyAlerts({
    athleteUid,
    athleteName,
    coachUid,
    previousRiskLevel: opts.previousRiskLevel,
    newRiskLevel: opts.newRiskLevel,
    lastCheckInAt: last,
    athleteCreatedAt: parseCreatedAt(opts.createdAt),
    syncIssue,
  });

  stats.riskSpikes = plan.riskSpikes;
  stats.missedCheckIns = plan.missedCheckIns;
  stats.syncFailures = plan.syncFailures;

  const notify = async (title: string, body: string, type: string) => {
    if (await sendPushToUser(athleteUid, title, body, { type, athleteUid })) {
      stats.pushes++;
    }
    if (coachUid) {
      if (
        await sendPushToUser(coachUid, title, body, {
          type,
          athleteUid,
          athleteName,
        })
      ) {
        stats.pushes++;
      }
    }
  };

  for (const alert of plan.athleteAlerts) {
    await writeAthleteAlert(alert.athleteUid, alert.docId, {
      title: alert.title,
      type: alert.type,
      timestamp: alert.timestamp,
    });
    const body =
      alert.type === 'risk_spike'
        ? 'Review the new recommendation in AthleteIQ.'
        : alert.type === 'missed_checkin'
          ? 'Open AthleteIQ and log fatigue, sleep, and training.'
          : (syncIssue ?? 'Wearable sync needs attention');
    await notify(alert.title, body, alert.type);
  }

  for (const alert of plan.coachAlerts) {
    await writeCoachAlert(alert.coachUid, alert.docId, {
      type: alert.type,
      urgency: alert.urgency,
      athleteUid: alert.athleteUid,
      athleteName: alert.athleteName,
      title: alert.title,
      summary: alert.summary,
      timestamp: alert.timestamp,
    });
  }

  return stats;
}
