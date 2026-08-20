/**
 * Live proof: create throwaway Auth users, seed Firestore, call
 * deleteAccount, confirm Auth + docs are gone. Never prints tokens.
 *
 *   cd functions && node scripts/verifyDeleteAccount.js
 *
 * Requires firebase login and a deployed `deleteAccount` callable.
 */
const path = require('path');
module.paths.push(path.join(path.dirname(process.execPath), 'node_modules'));
const toolsAuth = require('firebase-tools/lib/auth');
const toolsApiv2 = require('firebase-tools/lib/apiv2');

const PROJECT = 'athleteiq-app';
const WEB_KEY = 'AIzaSyDC_i4tdqWuUy8pVshNz8c0W27gOK-0lNQ';
const REGION = 'us-central1';
const FS = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

function attachCliAuth() {
  const account = toolsAuth.getGlobalDefaultAccount();
  if (!account?.tokens) throw new Error('firebase login required');
  toolsAuth.setActiveAccount({ project: PROJECT, projectId: PROJECT }, account);
  if (account.tokens.refresh_token) toolsApiv2.setRefreshToken(account.tokens.refresh_token);
  if (account.tokens.access_token) toolsApiv2.setAccessToken(account.tokens.access_token);
}

async function googleToken() {
  attachCliAuth();
  const t = await toolsApiv2.getAccessToken();
  if (!t) throw new Error('no Google access token');
  return t;
}

function toValue(v) {
  if (v === null) return { nullValue: null };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    return Number.isInteger(v)
      ? { integerValue: String(v) }
      : { doubleValue: v };
  }
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toValue) } };
  if (typeof v === 'object') {
    const fields = {};
    for (const [k, val] of Object.entries(v)) fields[k] = toValue(val);
    return { mapValue: { fields } };
  }
  throw new Error(`unsupported field ${typeof v}`);
}

function docBody(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) fields[k] = toValue(v);
  return { fields };
}

async function signUp(email, password) {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${WEB_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const json = await res.json();
  if (!json.idToken || !json.localId) {
    throw new Error(`signUp failed: ${json.error?.message || res.status}`);
  }
  return { idToken: json.idToken, uid: json.localId, email };
}

async function signIn(email, password) {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${WEB_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const json = await res.json();
  return {
    ok: res.ok && Boolean(json.idToken),
    idToken: json.idToken || null,
    uid: json.localId || null,
    message: json.error?.message || null,
  };
}

async function adminWrite(rel, data) {
  const res = await fetch(`${FS}/${rel}`, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${await googleToken()}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(docBody(data)),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(`write ${rel} -> ${res.status} ${json.error?.message || ''}`);
  }
}

async function adminGet(rel) {
  const res = await fetch(`${FS}/${rel}`, {
    headers: { Authorization: `Bearer ${await googleToken()}` },
  });
  return res.status;
}

async function adminDeleteAuth(uid) {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:delete`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${await googleToken()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ localId: uid }),
    },
  );
  return res.ok || res.status === 404;
}

async function adminDeleteDoc(rel) {
  const res = await fetch(`${FS}/${rel}`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${await googleToken()}` },
  });
  return res.ok || res.status === 404;
}

async function cleanupLeftovers(uid, role) {
  const paths = role === 'coach'
    ? [
        `coaches/${uid}/alerts/alert-1`,
        `coaches/${uid}/teamSettings/default`,
        `users/${uid}`,
        `coaches/${uid}`,
      ]
    : [
        `athletes/${uid}/checkins/2026-08-20`,
        `athletes/${uid}/devices/manual_tier3`,
        `athletes/${uid}/aiChat/msg-1`,
        `athletes/${uid}/messages/msg-1`,
        `athletes/${uid}/painReports/report-1`,
        `athletes/${uid}/alerts/alert-1`,
        `athletes/${uid}/riskResults/latest`,
        `users/${uid}`,
        `athletes/${uid}`,
      ];
  for (const rel of paths) {
    await adminDeleteDoc(rel);
  }
  await adminDeleteAuth(uid);
}

async function deleteAccountUrl() {
  return `https://${REGION}-${PROJECT}.cloudfunctions.net/deleteAccount`;
}

async function callDeleteAccount(idToken) {
  const url = await deleteAccountUrl();
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${idToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ data: { confirm: 'DELETE' } }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(
      `deleteAccount HTTP ${res.status}: ${json.error?.message || json.error?.status || JSON.stringify(json).slice(0, 240)}`,
    );
  }
  return json.result ?? json;
}

async function seedAthlete(uid, coachUid) {
  const now = new Date().toISOString();
  await adminWrite(`users/${uid}`, {
    role: 'athlete',
    name: 'Delete Test Athlete',
    email: `athlete-${uid.slice(0, 6)}@athleteiq.app`,
    createdAt: now,
  });
  await adminWrite(`athletes/${uid}`, {
    name: 'Delete Test Athlete',
    sport: 'Running / Athletics',
    sports: ['Running / Athletics'],
    sportGroup: 'endurance',
    coachUid,
    deviceTier: 'tier3',
    createdAt: now,
  });
  await adminWrite(`athletes/${uid}/checkins/2026-08-20`, {
    date: '2026-08-20',
    sessionDurationMinutes: 40,
    rpe: 6,
    fatigueScore: 3,
    source: 'manual',
  });
  await adminWrite(`athletes/${uid}/devices/manual_tier3`, {
    name: 'Manual entry',
    tier: 'tier3',
    connected: false,
    requiresWearableSync: false,
  });
  await adminWrite(`athletes/${uid}/aiChat/msg-1`, {
    senderUid: uid,
    text: 'delete-test',
    isAi: false,
  });
  await adminWrite(`athletes/${uid}/messages/msg-1`, {
    senderUid: uid,
    text: 'delete-test',
    isCoach: false,
  });
  await adminWrite(`athletes/${uid}/painReports/report-1`, {
    athleteUid: uid,
    date: now,
    areas: [{ location: 'Left knee', severity: 2 }],
    urgency: 'LOW',
  });
  await adminWrite(`athletes/${uid}/alerts/alert-1`, {
    title: 'delete-test',
    type: 'system',
    timestamp: now,
  });
  await adminWrite(`athletes/${uid}/riskResults/latest`, {
    riskLevel: 'LOW',
    recommendationStatus: 'pending',
    calculatedAt: now,
  });
}

async function seedCoach(uid, athleteUid) {
  const now = new Date().toISOString();
  await adminWrite(`users/${uid}`, {
    role: 'coach',
    name: 'Delete Test Coach',
    createdAt: now,
  });
  await adminWrite(`coaches/${uid}`, {
    name: 'Delete Test Coach',
    inviteCode: 'DELTST',
    createdAt: now,
  });
  await adminWrite(`coaches/${uid}/teamSettings/default`, {
    defaultActionPercent: 20,
    teamName: 'Delete Test Team',
  });
  await adminWrite(`coaches/${uid}/alerts/alert-1`, {
    type: 'pain',
    urgency: 'HIGH',
    athleteUid,
    title: 'delete-test',
    timestamp: now,
  });
  await adminWrite(`coaches/${uid}/inboxRead/${athleteUid}`, {
    lastReadAt: now,
  });
}

async function main() {
  const stamp = Date.now();
  const password = `DelTest-${stamp}!aA1`;
  const athleteEmail = `del.athlete.${stamp}@athleteiq.app`;
  const coachEmail = `del.coach.${stamp}@athleteiq.app`;

  const created = [];
  try {
    const athlete = await signUp(athleteEmail, password);
    created.push(athlete.uid);
    const coach = await signUp(coachEmail, password);
    created.push(coach.uid);
    console.log(`created athlete=${athlete.uid} coach=${coach.uid}`);

    await seedCoach(coach.uid, athlete.uid);
    await seedAthlete(athlete.uid, coach.uid);

    const beforeAthlete = await adminGet(`athletes/${athlete.uid}`);
    const beforeCoach = await adminGet(`coaches/${coach.uid}`);
    const beforeCheckin = await adminGet(`athletes/${athlete.uid}/checkins/2026-08-20`);
    if (beforeAthlete !== 200 || beforeCoach !== 200 || beforeCheckin !== 200) {
      throw new Error(`seed missing: athlete=${beforeAthlete} coach=${beforeCoach} checkin=${beforeCheckin}`);
    }

    const coachResult = await callDeleteAccount(coach.idToken);
    console.log(`coach deleteAccount: ${JSON.stringify(coachResult)}`);

    const coachAuth = await signIn(coachEmail, password);
    const coachDoc = await adminGet(`coaches/${coach.uid}`);
    const coachUser = await adminGet(`users/${coach.uid}`);
    const coachAlerts = await adminGet(`coaches/${coach.uid}/alerts/alert-1`);
    const athleteAfterUnlink = await adminGet(`athletes/${athlete.uid}`);
    const athleteProfileRes = await fetch(`${FS}/athletes/${athlete.uid}`, {
      headers: { Authorization: `Bearer ${await googleToken()}` },
    });
    const athleteProfile = await athleteProfileRes.json();
    const linkedCoach = athleteProfile.fields?.coachUid?.stringValue ?? null;

    if (coachAuth.ok) throw new Error('coach Auth user still signs in');
    if (coachDoc !== 404) throw new Error(`coach doc still present (${coachDoc})`);
    if (coachUser !== 404) throw new Error(`coach users doc still present (${coachUser})`);
    if (coachAlerts !== 404) throw new Error(`coach alerts still present (${coachAlerts})`);
    if (athleteAfterUnlink !== 200) throw new Error('athlete was deleted when coach was deleted');
    if (linkedCoach) throw new Error(`athlete still linked to ${linkedCoach}`);
    console.log('coach wipe ok; athlete unlinked and retained');

    const athleteRefresh = await signIn(athleteEmail, password);
    if (!athleteRefresh.ok || !athleteRefresh.idToken) {
      throw new Error('athlete Auth missing before athlete delete');
    }
    const athleteResult = await callDeleteAccount(athleteRefresh.idToken);
    console.log(`athlete deleteAccount: ${JSON.stringify(athleteResult)}`);

    const athleteAuth = await signIn(athleteEmail, password);
    const athleteDoc = await adminGet(`athletes/${athlete.uid}`);
    const athleteUser = await adminGet(`users/${athlete.uid}`);
    const checkin = await adminGet(`athletes/${athlete.uid}/checkins/2026-08-20`);
    const pain = await adminGet(`athletes/${athlete.uid}/painReports/report-1`);
    const device = await adminGet(`athletes/${athlete.uid}/devices/manual_tier3`);
    const chat = await adminGet(`athletes/${athlete.uid}/aiChat/msg-1`);
    const msg = await adminGet(`athletes/${athlete.uid}/messages/msg-1`);
    const alert = await adminGet(`athletes/${athlete.uid}/alerts/alert-1`);
    const risk = await adminGet(`athletes/${athlete.uid}/riskResults/latest`);

    const leftover = {
      athleteAuthOk: athleteAuth.ok,
      athleteDoc,
      athleteUser,
      checkin,
      pain,
      device,
      chat,
      msg,
      alert,
      risk,
    };
    const allGone =
      !athleteAuth.ok &&
      [athleteDoc, athleteUser, checkin, pain, device, chat, msg, alert, risk]
        .every((s) => s === 404);
    if (!allGone) {
      throw new Error(`athlete wipe incomplete: ${JSON.stringify(leftover)}`);
    }

    console.log(JSON.stringify({
      ok: true,
      coachUid: coach.uid,
      athleteUid: athlete.uid,
      coachAuthGone: !coachAuth.ok,
      athleteAuthGone: !athleteAuth.ok,
      firestoreGone: true,
      unlinkedAthletes: coachResult.unlinkedAthletes ?? null,
    }));
  } catch (err) {
    console.error(err.message || err);
    for (const uid of created) {
      try {
        await cleanupLeftovers(uid, uid === created[1] ? 'coach' : 'athlete');
      } catch (_) {
        /* best-effort cleanup */
      }
    }
    process.exit(1);
  }
}

main();
