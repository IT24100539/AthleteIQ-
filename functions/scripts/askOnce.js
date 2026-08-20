/**
 * One production askAthleteIQ call. Never prints tokens.
 */
const WEB_KEY = 'AIzaSyDC_i4tdqWuUy8pVshNz8c0W27gOK-0lNQ';
const PROJECT = 'athleteiq-app';
const EMAIL = 'demo.athlete@athleteiq.app';
const PASSWORD = 'Demo1234!';
const FALLBACK =
  "I don't have a live model answer right now. Check your latest risk result " +
  'and recent sleep/fatigue logs — that combination is usually why fatigue and risk go up.';

async function main() {
  const auth = await fetch(
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
  ).then((r) => r.json());
  if (!auth.idToken) throw new Error(`sign-in failed: ${auth.error?.message}`);

  const question =
    'Why am I so tired this week? What do my latest sleep, fatigue, and load numbers actually show?';
  const res = await fetch(
    `https://us-central1-${PROJECT}.cloudfunctions.net/askAthleteIQ`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${auth.idToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        data: { athleteUid: auth.localId, question },
      }),
    },
  );
  const json = await res.json();
  const result = json.result ?? json;
  const text = result.text ?? '';
  console.log(
    JSON.stringify(
      {
        http: res.status,
        athleteUid: auth.localId,
        question,
        source: result.source ?? null,
        text,
        matchesFallbackAnswer: text === FALLBACK,
        error: json.error ?? null,
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
