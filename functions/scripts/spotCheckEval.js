/**
 * Human spot-check of stored LLM-as-judge records for Alex Rivera.
 *
 * List:
 *   node scripts/spotCheckEval.js
 *
 * Flag:
 *   node scripts/spotCheckEval.js --id EVAL_ID --agree
 *   node scripts/spotCheckEval.js --id EVAL_ID --disagree --items grounding,medical --note "judge rewarded length"
 *
 * Never prints tokens or keys.
 */
const WEB_KEY = 'AIzaSyDC_i4tdqWuUy8pVshNz8c0W27gOK-0lNQ';
const PROJECT = 'athleteiq-app';
const EMAIL = 'demo.athlete@athleteiq.app';
const PASSWORD = 'Demo1234!';

function arg(name) {
  const i = process.argv.indexOf(name);
  if (i === -1) return undefined;
  return process.argv[i + 1];
}

function hasFlag(name) {
  return process.argv.includes(name);
}

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

function fromValue(v) {
  if (!v) return null;
  if (v.stringValue != null) return v.stringValue;
  if (v.integerValue != null) return Number(v.integerValue);
  if (v.doubleValue != null) return v.doubleValue;
  if (v.booleanValue != null) return v.booleanValue;
  if (v.timestampValue != null) return v.timestampValue;
  if (v.nullValue !== undefined) return null;
  if (v.mapValue) return fromFields(v.mapValue.fields || {});
  if (v.arrayValue) return (v.arrayValue.values || []).map(fromValue);
  return null;
}

function fromFields(fields) {
  const out = {};
  for (const [k, v] of Object.entries(fields || {})) out[k] = fromValue(v);
  return out;
}

async function listEvals(token, uid) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/` +
    `athletes/${uid}/llmEvaluations?pageSize=20&orderBy=judgedAt%20desc`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  const json = await res.json();
  if (!res.ok) {
    throw new Error(json.error?.message || `firestore list ${res.status}`);
  }
  return (json.documents || []).map((doc) => {
    const id = doc.name.split('/').pop();
    const d = fromFields(doc.fields);
    return {
      evalId: id,
      kind: d.kind,
      judgedAt: d.judgedAt,
      overallScore: d.overallScore,
      overallPass: d.overallPass,
      verbosityBiasRisk: d.verbosityBiasRisk,
      summary: d.summary,
      humanReview: d.humanReview,
      items: (d.items || []).map((i) => ({
        id: i.id,
        pass: i.pass,
        evidence: i.evidence,
        reason: i.reason,
      })),
      outputPreview: d.outputPreview,
    };
  });
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
  const evalId = arg('--id');

  if (!evalId) {
    const rows = await listEvals(athlete.idToken, athlete.uid);
    console.log(
      JSON.stringify(
        {
          athleteUid: athlete.uid,
          count: rows.length,
          evaluations: rows,
          howToSpotCheck: {
            agree: 'node scripts/spotCheckEval.js --id EVAL_ID --agree',
            disagree:
              'node scripts/spotCheckEval.js --id EVAL_ID --disagree --items grounding,medical --note "why the judge was wrong"',
          },
        },
        null,
        2,
      ),
    );
    return;
  }

  const agreement = hasFlag('--disagree') ? 'disagree' : 'agree';
  if (!hasFlag('--agree') && !hasFlag('--disagree')) {
    throw new Error('Pass --agree or --disagree with --id');
  }
  const itemsRaw = arg('--items') || '';
  const review = await callFn(athlete.idToken, 'reviewLlmEvaluation', {
    athleteUid: athlete.uid,
    evalId,
    agreement,
    disagreedItemIds: itemsRaw
      ? itemsRaw.split(',').map((s) => s.trim()).filter(Boolean)
      : [],
    note: arg('--note') || '',
  });
  console.log(
    JSON.stringify(
      {
        http: review.http,
        evalId,
        error: review.body.error || null,
        result: review.body.result || null,
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
