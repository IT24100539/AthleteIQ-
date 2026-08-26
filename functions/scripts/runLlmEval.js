/**
 * First-pass LLM-as-judge against Alex Rivera's stored outputs.
 * Never prints tokens or keys.
 *
 *   node scripts/runLlmEval.js
 */
const WEB_KEY = 'AIzaSyDC_i4tdqWuUy8pVshNz8c0W27gOK-0lNQ';
const PROJECT = 'athleteiq-app';
const EMAIL = 'demo.athlete@athleteiq.app';
const PASSWORD = 'Demo1234!';

const KINDS = ['askAthleteIQ', 'orchestrator', 'graded', 'explain', 'research'];

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

function summarize(result) {
  if (result.skipped) {
    return { kind: result.kind, skipped: true, skipReason: result.skipReason };
  }
  const rec = result.record || {};
  return {
    kind: result.kind,
    evalId: result.evalId,
    overallScore: rec.overallScore,
    overallPass: rec.overallPass,
    judgeOverallScore: rec.judgeOverallScore,
    verbosityBiasRisk: rec.verbosityBiasRisk,
    generatorSource: rec.generatorSource,
    summary: rec.summary,
    items: (rec.items || []).map((i) => ({
      id: i.id,
      pass: i.pass,
      evidence: i.evidence,
      reason: i.reason,
    })),
  };
}

async function main() {
  const athlete = await signIn();
  const call = await callFn(athlete.idToken, 'evaluateAthleteLlmHistory', {
    athleteUid: athlete.uid,
    kinds: KINDS,
  });
  const payload = call.body.result || {};
  const results = Array.isArray(payload.results) ? payload.results : [];
  console.log(
    JSON.stringify(
      {
        http: call.http,
        athleteUid: athlete.uid,
        athleteName: 'Alex Rivera',
        error: call.body.error || null,
        results: results.map(summarize),
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
