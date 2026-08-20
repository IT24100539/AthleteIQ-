/**
 * Admin backfill + live rules fetch via Firebase CLI Google OAuth (Console
 * privileges; bypasses security rules). Never logs tokens.
 */
const path = require('path');
module.paths.push(path.join(path.dirname(process.execPath), 'node_modules'));

const toolsAuth = require('firebase-tools/lib/auth');
const toolsApiv2 = require('firebase-tools/lib/apiv2');
const { buildAthleteRiskView, buildCheckInCoachView } = require('../lib/privacyViews');
const { parsePrivacySettings } = require('../lib/privacySettings');

const PROJECT = 'athleteiq-app';
const FS = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)`;
const RULES = `https://firebaserules.googleapis.com/v1/projects/${PROJECT}`;

function attachCliAuth() {
  const account = toolsAuth.getGlobalDefaultAccount();
  if (!account || !account.tokens) {
    throw new Error('No Firebase CLI login. Run firebase login.');
  }
  const opts = { project: PROJECT, projectId: PROJECT };
  toolsAuth.setActiveAccount(opts, account);
  if (account.tokens.refresh_token) {
    toolsApiv2.setRefreshToken(account.tokens.refresh_token);
  }
  if (account.tokens.access_token) {
    toolsApiv2.setAccessToken(account.tokens.access_token);
  }
}

async function token() {
  attachCliAuth();
  const t = await toolsApiv2.getAccessToken();
  if (!t) throw new Error('Could not obtain Google access token.');
  return t;
}

async function api(method, url, body) {
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${await token()}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(`${method} ${url} -> ${res.status} ${json.error?.message || JSON.stringify(json).slice(0, 300)}`);
  }
  return json;
}

function fromValue(v) {
  if (!v) return null;
  if (v.stringValue != null) return v.stringValue;
  if (v.integerValue != null) return Number(v.integerValue);
  if (v.doubleValue != null) return v.doubleValue;
  if (v.booleanValue != null) return v.booleanValue;
  if (v.timestampValue != null) return { __ts: v.timestampValue };
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

function toValue(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (v && typeof v === 'object' && v.__ts) return { timestampValue: v.__ts };
  if (typeof v === 'string') return { stringValue: v };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toValue) } };
  if (typeof v === 'object') {
    const fields = {};
    for (const [k, val] of Object.entries(v)) {
      if (val !== undefined) fields[k] = toValue(val);
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(v) };
}

function toDoc(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v !== undefined) fields[k] = toValue(v);
  }
  return { fields };
}

function docId(name) {
  return name.split('/').pop();
}

async function listDocs(relPath) {
  const json = await api('GET', `${FS}/documents/${relPath}?pageSize=300`);
  return json.documents || [];
}

async function writeDoc(relPath, obj) {
  await api('PATCH', `${FS}/documents/${relPath}`, toDoc(obj));
}

async function fetchLiveRulesSource() {
  const release = await api('GET', `${RULES}/releases/cloud.firestore`);
  if (!release.rulesetName) {
    throw new Error('No ruleset on cloud.firestore release.');
  }
  const rs = await api('GET', `https://firebaserules.googleapis.com/v1/${release.rulesetName}`);
  const source = rs.source?.files?.[0]?.content;
  if (!source) throw new Error('Ruleset had no source content.');
  return { rulesetName: release.rulesetName, createTime: rs.createTime, source };
}

async function backfill() {
  const athletes = await listDocs('athletes');
  const summary = [];
  for (const athlete of athletes) {
    const uid = docId(athlete.name);
    const data = fromFields(athlete.fields);
    const privacy = parsePrivacySettings(data.privacySettings);
    const checkins = await listDocs(`athletes/${uid}/checkins`);
    let viewsBefore = [];
    try {
      viewsBefore = await listDocs(`athletes/${uid}/checkinsCoachView`);
    } catch (_) {
      viewsBefore = [];
    }

    for (const c of checkins) {
      const id = docId(c.name);
      const view = buildCheckInCoachView(fromFields(c.fields), privacy);
      await writeDoc(`athletes/${uid}/checkinsCoachView/${id}`, view);
    }

    let athleteViewWrote = false;
    try {
      const latestList = await listDocs(`athletes/${uid}/riskResults`);
      const latest = latestList.find((d) => docId(d.name) === 'latest');
      if (latest) {
        await writeDoc(
          `athletes/${uid}/riskResults/athleteView`,
          buildAthleteRiskView(fromFields(latest.fields)),
        );
        athleteViewWrote = true;
      }
    } catch (err) {
      // keep going; report below
      summary.push({
        athleteUid: uid,
        error: String(err.message || err),
      });
      continue;
    }

    const viewsAfter = await listDocs(`athletes/${uid}/checkinsCoachView`);
    summary.push({
      athleteUid: uid,
      name: data.name || null,
      coachUid: data.coachUid || null,
      rawCheckins: checkins.length,
      coachViewBefore: viewsBefore.length,
      coachViewAfter: viewsAfter.length,
      athleteViewWrote,
    });
  }
  return summary;
}

async function main() {
  const cmd = process.argv[2] || 'backfill';
  if (cmd === 'rules') {
    const live = await fetchLiveRulesSource();
    console.log(`ruleset=${live.rulesetName}`);
    console.log(`createTime=${live.createTime}`);
    console.log('---BEGIN RULES---');
    console.log(live.source);
    console.log('---END RULES---');
    return;
  }
  if (cmd === 'backfill') {
    const summary = await backfill();
    console.log(JSON.stringify({ athletes: summary.length, summary }, null, 2));
    return;
  }
  throw new Error(`Unknown command ${cmd}`);
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
