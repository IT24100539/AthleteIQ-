/**
 * Account deletion — Admin SDK only. Clients call `deleteAccount`; they
 * cannot bulk-delete subcollections or remove the Auth user themselves.
 */
import { getAuth } from 'firebase-admin/auth';
import {
  CollectionReference,
  DocumentReference,
  getFirestore,
} from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError } from 'firebase-functions/v2/https';

/** Subcollections under `athletes/{uid}`. Keep in sync with firestore.rules. */
export const ATHLETE_SUBCOLLECTIONS = [
  'checkins',
  'checkinsCoachView',
  'riskResults',
  'devices',
  'aiChat',
  'messages',
  'painReports',
  'alerts',
  'orchestratorTraces',
  'weeklyReports',
] as const;

/** Subcollections under `coaches/{uid}`. Keep in sync with firestore.rules. */
export const COACH_SUBCOLLECTIONS = [
  'alerts',
  'teamSettings',
  'inboxRead',
] as const;

const BATCH_LIMIT = 400;

export type DeleteAccountResult = {
  role: string | null;
  unlinkedAthletes: number;
  authDeleted: boolean;
};

async function commitDeletes(refs: DocumentReference[]): Promise<void> {
  const db = getFirestore();
  for (let i = 0; i < refs.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const ref of refs.slice(i, i + BATCH_LIMIT)) {
      batch.delete(ref);
    }
    await batch.commit();
  }
}

async function deleteCollection(col: CollectionReference): Promise<number> {
  let deleted = 0;
  for (;;) {
    const snap = await col.limit(BATCH_LIMIT).get();
    if (snap.empty) break;
    await commitDeletes(snap.docs.map((d) => d.ref));
    deleted += snap.size;
    if (snap.size < BATCH_LIMIT) break;
  }
  return deleted;
}

async function deleteDocTree(
  ref: DocumentReference,
  subcollections: readonly string[],
): Promise<void> {
  for (const name of subcollections) {
    await deleteCollection(ref.collection(name));
  }
  const snap = await ref.get();
  if (snap.exists) {
    await ref.delete();
  }
}

async function unlinkAthletesFromCoach(coachUid: string): Promise<number> {
  const db = getFirestore();
  const roster = await db
    .collection('athletes')
    .where('coachUid', '==', coachUid)
    .get();
  if (roster.empty) return 0;

  const docs = roster.docs;
  for (let i = 0; i < docs.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const doc of docs.slice(i, i + BATCH_LIMIT)) {
      batch.update(doc.ref, { coachUid: null });
    }
    await batch.commit();
  }
  return docs.length;
}

/** Drop coach-owned pointers at a deleted athlete (alerts + inbox read). */
async function deleteCoachArtifactsForAthlete(
  coachUid: string,
  athleteUid: string,
): Promise<void> {
  const db = getFirestore();
  const coachRef = db.collection('coaches').doc(coachUid);
  const alerts = await coachRef
    .collection('alerts')
    .where('athleteUid', '==', athleteUid)
    .get();
  await commitDeletes(alerts.docs.map((d) => d.ref));
  await coachRef.collection('inboxRead').doc(athleteUid).delete();
}

/**
 * Wipe Firestore + Auth for `uid`. Idempotent: missing docs/users are OK.
 * Unlinks roster athletes instead of deleting their accounts.
 */
export async function deleteAccountForUid(
  uid: string,
): Promise<DeleteAccountResult> {
  const db = getFirestore();
  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();
  const role = (userSnap.data()?.role as string | undefined) ?? null;

  const athleteRef = db.collection('athletes').doc(uid);
  const athleteSnap = await athleteRef.get();
  const coachRef = db.collection('coaches').doc(uid);
  const coachSnap = await coachRef.get();

  let unlinkedAthletes = 0;

  if (coachSnap.exists) {
    unlinkedAthletes = await unlinkAthletesFromCoach(uid);
    await deleteDocTree(coachRef, COACH_SUBCOLLECTIONS);
  }

  if (athleteSnap.exists) {
    const coachUid = athleteSnap.data()?.coachUid;
    if (typeof coachUid === 'string' && coachUid.trim().length > 0) {
      await deleteCoachArtifactsForAthlete(coachUid.trim(), uid);
    }
    await deleteDocTree(athleteRef, ATHLETE_SUBCOLLECTIONS);
  }

  if (userSnap.exists) {
    await userRef.delete();
  }

  let authDeleted = false;
  try {
    await getAuth().deleteUser(uid);
    authDeleted = true;
  } catch (err: unknown) {
    const code = (err as { code?: string }).code;
    if (code === 'auth/user-not-found') {
      authDeleted = true;
    } else {
      logger.error('Auth user delete failed after Firestore wipe', { uid, err });
      throw new HttpsError(
        'internal',
        'Your data was removed but the sign-in account could not be deleted. Try again.',
      );
    }
  }

  logger.info('deleteAccount finished', {
    uid,
    role,
    unlinkedAthletes,
    authDeleted,
  });

  return { role, unlinkedAthletes, authDeleted };
}
