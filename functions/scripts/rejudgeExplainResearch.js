/**
 * Re-judge explain + research with the context the production loader uses.
 * Never prints keys.
 */
const fs = require('fs');
const path = require('path');

function loadEnvFile(filename) {
  const envPath = path.join(__dirname, '..', filename);
  if (!fs.existsSync(envPath)) return;
  const raw = fs.readFileSync(envPath, 'utf8');
  for (const line of raw.split(/\r?\n/)) {
    if (!line || line.trim().startsWith('#')) continue;
    const i = line.indexOf('=');
    if (i < 1) continue;
    const k = line.slice(0, i).trim();
    let v = line.slice(i + 1).trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      v = v.slice(1, -1);
    }
    if (process.env[k] === undefined) process.env[k] = v;
  }
}
loadEnvFile('.env');
loadEnvFile('.secret.local');

const WEB_KEY = 'AIzaSyDC_i4tdqWuUy8pVshNz8c0W27gOK-0lNQ';
const PROJECT = 'athleteiq-app';
const ATHLETE_EMAIL = 'demo.athlete@athleteiq.app';
const COACH_EMAIL = 'demo.coach@athleteiq.app';
const PASSWORD = 'Demo1234!';

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
  if (!json.idToken) throw new Error(json.error?.message);
  return { idToken: json.idToken, uid: json.localId };
}

function fromValue(v) {
  if (!v) return null;
  if (v.stringValue != null) return v.stringValue;
  if (v.integerValue != null) return Number(v.integerValue);
  if (v.doubleValue != null) return v.doubleValue;
  if (v.booleanValue != null) return v.booleanValue;
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
async function fsGet(token, rel) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${rel}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  const json = await res.json();
  return json.fields ? fromFields(json.fields) : {};
}
async function fsList(token, rel, orderBy, pageSize = 14) {
  let url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${rel}?pageSize=${pageSize}`;
  if (orderBy) url += `&orderBy=${encodeURIComponent(orderBy)}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  const json = await res.json();
  return (json.documents || []).map((d) => ({ id: d.name.split('/').pop(), ...fromFields(d.fields) }));
}

function compact(judged, extra) {
  return {
    ...extra,
    overallScore: judged.overallScore,
    overallPass: judged.overallPass,
    judgeOverallScore: judged.judgeOverallScore,
    summary: judged.summary,
    items: judged.items.map((i) => ({ id: i.id, pass: i.pass, evidence: i.evidence, reason: i.reason })),
  };
}

async function main() {
  const { judgeOutput } = require('../lib/evaluation/judge');
  const athlete = await signIn(ATHLETE_EMAIL);
  const coach = await signIn(COACH_EMAIL);
  const d = await fsGet(coach.idToken, `athletes/${athlete.uid}/riskResults/latest`);
  const checkins = await fsList(athlete.idToken, `athletes/${athlete.uid}/checkins`, 'date desc', 5);
  const last5 = checkins
    .slice(0, 5)
    .map((c) => {
      const load = (c.sessionDurationMinutes || 0) * (c.rpe || 0);
      return `  ${c.date || c.id}: fatigue ${c.fatigueScore}/5, load ${load}, sleep ${c.sleepHours ?? 'n/a'}h, HRV ${c.hrv ?? 'n/a'}, rHR ${c.restingHeartRate ?? 'n/a'}`;
    })
    .join('\n');
  const snapshot = [
    `LOCKED riskLevel: ${d.riskLevel}`,
    `LOCKED performancePrediction: ${d.performancePrediction} (${d.performanceFrame || ''})`,
    `ACWR: ${d.acwr}`,
    `7-day load: ${d.trainingLoad7d}`,
    `28-day avg weekly load: ${d.trainingLoad28dAvg}`,
    `Recovery trend: ${d.recoveryTrend}`,
    `Rule-based reason: ${d.reason}`,
  ].join('\n');

  const explain = await judgeOutput({
    kind: 'explain',
    outputText: JSON.stringify({
      riskLevelReasoningLLM: d.riskLevelReasoningLLM,
      riskLevelPatternFlag: d.riskLevelPatternFlag,
      performanceReasoningLLM: d.performanceReasoningLLM,
    }, null, 2),
    contextText: `${snapshot}\nLast 5 check-ins:\n${last5}`,
  });

  const corpus = ['acwr.md', 'session-rpe.md', 'banister-fitness-fatigue.md']
    .map((f) => fs.readFileSync(path.join(__dirname, '..', 'knowledge', f), 'utf8'))
    .join('\n\n---\n\n');
  const research = await judgeOutput({
    kind: 'research',
    outputText: JSON.stringify({ note: d.researchNote, citations: d.researchCitations || [] }, null, 2),
    contextText: `${snapshot}\n\nRetrieved notes:\n${corpus}`,
  });

  console.log(JSON.stringify({
    explain: compact(explain, { kind: 'explain', generatorSource: d.explanationSource }),
    research: compact(research, { kind: 'research', generatorSource: d.researchSource }),
  }, null, 2));
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
