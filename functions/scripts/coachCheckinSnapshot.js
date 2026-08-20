/**
 * Sign in as the demo coach and report what Firestore actually returns
 * for raw checkins vs checkinsCoachView. Does not print auth tokens.
 */
const WEB_KEY = 'AIzaSyDC_i4tdqWuUy8pVshNz8c0W27gOK-0lNQ';
const PROJECT = 'athleteiq-app';
const EMAIL = 'demo.coach@athleteiq.app';
const PASSWORD = 'Demo1234!';

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
  if (!json.idToken || !json.localId) {
    throw new Error(`Sign-in failed: ${json.error?.message || res.status}`);
  }
  return { idToken: json.idToken, uid: json.localId };
}

function fsUrl(path, qs = '') {
  const base = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
  return `${base}/${path}${qs}`;
}

async function fsGet(idToken, path) {
  const res = await fetch(fsUrl(path), {
    headers: { Authorization: `Bearer ${idToken}` },
  });
  const json = await res.json();
  return { status: res.status, json };
}

async function fsList(idToken, path) {
  const res = await fetch(fsUrl(path, '?pageSize=100'), {
    headers: { Authorization: `Bearer ${idToken}` },
  });
  const json = await res.json();
  return { status: res.status, json };
}

async function runQuery(idToken, structuredQuery) {
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:runQuery`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${idToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ structuredQuery }),
    },
  );
  return res.json();
}

function fieldsOf(doc) {
  const f = doc.fields || {};
  return Object.keys(f).sort();
}

function sample(doc) {
  const f = doc.fields || {};
  const out = {};
  for (const [k, v] of Object.entries(f)) {
    if (v.stringValue != null) out[k] = v.stringValue;
    else if (v.integerValue != null) out[k] = Number(v.integerValue);
    else if (v.doubleValue != null) out[k] = v.doubleValue;
    else if (v.timestampValue != null) out[k] = v.timestampValue;
    else out[k] = Object.keys(v)[0];
  }
  return out;
}

async function main() {
  const label = process.argv[2] || 'snapshot';
  const { idToken, uid } = await signIn();
  console.log(`\n=== ${label} ===`);
  console.log(`coachUid=${uid} email=${EMAIL}`);

  const roster = await runQuery(idToken, {
    from: [{ collectionId: 'athletes' }],
    where: {
      fieldFilter: {
        field: { fieldPath: 'coachUid' },
        op: 'EQUAL',
        value: { stringValue: uid },
      },
    },
  });

  const athletes = (Array.isArray(roster) ? roster : [])
    .map((row) => row.document)
    .filter(Boolean);

  const fallbackUids = process.argv.slice(3);
  if (athletes.length === 0 && fallbackUids.length) {
    console.log(`roster query returned ${athletes.length}; using fallback athlete docs`);
    for (const uid of fallbackUids) {
      const got = await fsGet(idToken, `athletes/${uid}`);
      if (got.status === 200 && got.json.name) {
        athletes.push(got.json);
      } else {
        console.log(`athlete ${uid} HTTP ${got.status} ${got.json.error?.status || got.json.error?.message || ''}`);
      }
    }
  }

  console.log(`roster size=${athletes.length}`);
  if (athletes.length === 0) {
    console.log('No athletes on this coach roster (query may have failed):');
    console.log(JSON.stringify(roster, null, 2).slice(0, 1500));
    return;
  }

  for (const athlete of athletes) {
    const name = athlete.name.split('/').pop();
    const display = athlete.fields?.name?.stringValue || '(unnamed)';
    console.log(`\nathlete ${name} (${display})`);

    const raw = await fsList(idToken, `athletes/${name}/checkins`);
    const view = await fsList(idToken, `athletes/${name}/checkinsCoachView`);

    const rawDocs = raw.json.documents || [];
    const viewDocs = view.json.documents || [];
    const rawErr = raw.json.error?.status || raw.json.error?.message;
    const viewErr = view.json.error?.status || view.json.error?.message;

    console.log(
      `  checkins/          HTTP ${raw.status} count=${rawDocs.length}` +
        (rawErr ? ` error=${rawErr}` : ''),
    );
    console.log(
      `  checkinsCoachView/ HTTP ${view.status} count=${viewDocs.length}` +
        (viewErr ? ` error=${viewErr}` : ''),
    );

    if (rawDocs[0]) {
      console.log(`  raw sample id=${rawDocs[0].name.split('/').pop()} keys=${fieldsOf(rawDocs[0]).join(',')}`);
      console.log(`  raw sample fields=${JSON.stringify(sample(rawDocs[0]))}`);
    }
    if (viewDocs[0]) {
      console.log(`  view sample id=${viewDocs[0].name.split('/').pop()} keys=${fieldsOf(viewDocs[0]).join(',')}`);
      console.log(`  view sample fields=${JSON.stringify(sample(viewDocs[0]))}`);
    }
    if (!rawDocs[0] && !viewDocs[0]) {
      console.log('  (both collections empty or denied for this coach)');
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
