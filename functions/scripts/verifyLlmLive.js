/**
 * Production LLM proof for askAthleteIQ + submitPainReport.
 * Never prints tokens or the API key.
 */
const WEB_KEY = 'AIzaSyDC_i4tdqWuUy8pVshNz8c0W27gOK-0lNQ';
const PROJECT = 'athleteiq-app';
const EMAIL = 'demo.athlete@athleteiq.app';
const PASSWORD = 'Demo1234!';
const FALLBACK =
  "I don't have a live model answer right now. Check your latest risk result " +
  'and recent sleep/fatigue logs — that combination is usually why fatigue and risk go up.';

async function signIn() {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${WEB_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: EMAIL,
        password: PASSWORD,
        returnSecureToken: true,
      }),
    },
  );
  const json = await res.json();
  if (!json.idToken) throw new Error(`sign-in failed: ${json.error?.message}`);
  return { idToken: json.idToken, uid: json.localId };
}

async function callFn(token, name, data) {
  const res = await fetch(
    `https://us-central1-${PROJECT}.cloudfunctions.net/${name}`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ data }),
    },
  );
  const json = await res.json();
  return { http: res.status, body: json };
}

async function main() {
  const athlete = await signIn();

  const ask = await callFn(athlete.idToken, 'askAthleteIQ', {
    athleteUid: athlete.uid,
    question:
      'Why am I so tired this week? What do my latest sleep, fatigue, and load numbers actually show?',
  });
  const askResult = ask.body.result || {};

  const pain = await callFn(athlete.idToken, 'submitPainReport', {
    athleteUid: athlete.uid,
    areas: [{ location: 'Right hamstring', severity: 3 }],
    note:
      'Familiar hamstring tightness after a hard session. Improving today. I can still train as planned.',
  });
  const painResult = pain.body.result || {};

  console.log(
    JSON.stringify(
      {
        athleteUid: athlete.uid,
        askAthleteIQ: {
          http: ask.http,
          source: askResult.source ?? null,
          text: askResult.text ?? null,
          matchesStaticFallback: askResult.text === FALLBACK,
          error: ask.body.error ?? null,
        },
        submitPainReport: {
          http: pain.http,
          source: painResult.urgencySource ?? null,
          urgency: painResult.urgency ?? null,
          urgencyReason: painResult.urgencyReason ?? null,
          reportId: painResult.reportId ?? null,
          error: pain.body.error ?? null,
        },
      },
      null,
      2,
    ),
  );
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
