/**
 * Production E2E: athlete writes a check-in, calls recalculateRisk,
 * coach reads checkinsCoachView. Never prints tokens.
 */
const WEB_KEY = 'AIzaSyDC_i4tdqWuUy8pVshNz8c0W27gOK-0lNQ';
const PROJECT = 'athleteiq-app';
const ATHLETE_EMAIL = 'demo.athlete@athleteiq.app';
const COACH_EMAIL = 'demo.coach@athleteiq.app';
const PASSWORD = 'Demo1234!';
const ATHLETE_UID = '7o54AyrYprTUyTJzpKzXdz90lH33';
const DATE_KEY = '2026-08-18';
const MARKER = 'e2e-blaze-deploy';

async function signIn(email) {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${WEB_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: PASSWORD, returnSecureToken: true }),
    },
  );
  const json = await res.json();
  if (!json.idToken) throw new Error(`Sign-in failed for ${email}: ${json.error?.message}`);
  return { idToken: json.idToken, uid: json.localId };
}

function docUrl(rel) {
  return `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${rel}`;
}

async function fsGet(token, rel) {
  const res = await fetch(docUrl(rel), { headers: { Authorization: `Bearer ${token}` } });
  return { status: res.status, json: await res.json() };
}

function sourceOf(json) {
  return json?.fields?.source?.stringValue ?? null;
}

function minsOf(json) {
  const v = json?.fields?.sessionDurationMinutes;
  if (!v) return null;
  return v.integerValue != null ? Number(v.integerValue) : v.doubleValue ?? null;
}

async function main() {
  const athlete = await signIn(ATHLETE_EMAIL);
  const coach = await signIn(COACH_EMAIL);
  console.log(`athleteUid=${athlete.uid} coachUid=${coach.uid}`);
  if (athlete.uid !== ATHLETE_UID) {
    console.log(`note: signed-in athlete uid differs from expected ${ATHLETE_UID}`);
  }

  const viewPath = `athletes/${athlete.uid}/checkinsCoachView/${DATE_KEY}`;
  const rawPath = `athletes/${athlete.uid}/checkins/${DATE_KEY}`;

  const beforeCoachRaw = await fsGet(coach.idToken, rawPath);
  const beforeCoachView = await fsGet(coach.idToken, viewPath);
  console.log(
    JSON.stringify({
      before: {
        coachRawHttp: beforeCoachRaw.status,
        coachViewHttp: beforeCoachView.status,
        coachViewSource: sourceOf(beforeCoachView.json),
        coachViewMinutes: minsOf(beforeCoachView.json),
      },
    }),
  );

  const nowIso = new Date().toISOString();
  const writeRes = await fetch(`${docUrl(rawPath)}?currentDocument.exists=false`, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${athlete.idToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      fields: {
        date: { timestampValue: `${DATE_KEY}T12:00:00Z` },
        sessionDurationMinutes: { integerValue: '42' },
        rpe: { integerValue: '7' },
        fatigueScore: { integerValue: '4' },
        sleepHours: { doubleValue: 6.5 },
        source: { stringValue: MARKER },
      },
    }),
  });
  // exists=false fails if doc exists; retry as merge/update
  let writeJson = await writeRes.json();
  if (!writeRes.ok) {
    const retry = await fetch(docUrl(rawPath), {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${athlete.idToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        fields: {
          date: { timestampValue: `${DATE_KEY}T12:00:00Z` },
          sessionDurationMinutes: { integerValue: '42' },
          rpe: { integerValue: '7' },
          fatigueScore: { integerValue: '4' },
          sleepHours: { doubleValue: 6.5 },
          source: { stringValue: MARKER },
        },
      }),
    });
    writeJson = await retry.json();
    console.log(`checkin write HTTP ${retry.status} (update)`);
  } else {
    console.log(`checkin write HTTP ${writeRes.status} (create)`);
  }
  if (writeJson.error) {
    throw new Error(`check-in write failed: ${writeJson.error.message}`);
  }

  const callRes = await fetch(
    `https://us-central1-${PROJECT}.cloudfunctions.net/recalculateRisk`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${athlete.idToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ data: { athleteUid: athlete.uid } }),
    },
  );
  const callJson = await callRes.json();
  console.log(
    JSON.stringify({
      recalculateRisk: { http: callRes.status, result: callJson.result ?? callJson },
    }),
  );

  let after = null;
  for (let i = 0; i < 12; i++) {
    await new Promise((r) => setTimeout(r, 5000));
    const view = await fsGet(coach.idToken, viewPath);
    const raw = await fsGet(coach.idToken, rawPath);
    after = {
      attempt: i + 1,
      waitedSec: (i + 1) * 5,
      coachRawHttp: raw.status,
      coachViewHttp: view.status,
      coachViewSource: sourceOf(view.json),
      coachViewMinutes: minsOf(view.json),
      coachViewRpe: view.json?.fields?.rpe?.integerValue ?? null,
      coachViewFatigue: view.json?.fields?.fatigueScore?.integerValue ?? null,
    };
    console.log(`poll ${after.attempt}: view HTTP ${after.coachViewHttp} source=${after.coachViewSource} mins=${after.coachViewMinutes}`);
    if (after.coachViewHttp === 200 && after.coachViewSource === MARKER && after.coachViewMinutes === 42) {
      break;
    }
  }

  console.log(JSON.stringify({ after, wroteAt: nowIso }, null, 2));
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
