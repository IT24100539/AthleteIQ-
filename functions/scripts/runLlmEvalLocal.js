/**
 * Local first-pass judge against Alex Rivera's production Firestore.
 * Uses REST reads + ANTHROPIC_API_KEY from functions/.env or .secret.local.
 * Does not deploy. Never prints keys.
 *
 *   node scripts/runLlmEvalLocal.js
 */
const fs = require('fs');
const path = require('path');

const WEB_KEY = 'AIzaSyDC_i4tdqWuUy8pVshNz8c0W27gOK-0lNQ';
const PROJECT = 'athleteiq-app';
const ATHLETE_EMAIL = 'demo.athlete@athleteiq.app';
const COACH_EMAIL = 'demo.coach@athleteiq.app';
const PASSWORD = 'Demo1234!';

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
  if (!json.idToken) throw new Error(`Sign-in failed (${email}): ${json.error?.message}`);
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

async function fsGet(token, rel) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${rel}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  const json = await res.json();
  return { status: res.status, data: json.fields ? fromFields(json.fields) : json };
}

async function fsList(token, rel, orderBy, pageSize = 20) {
  let url =
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${rel}?pageSize=${pageSize}`;
  if (orderBy) url += `&orderBy=${encodeURIComponent(orderBy)}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  const json = await res.json();
  return (json.documents || []).map((d) => ({
    id: d.name.split('/').pop(),
    ...fromFields(d.fields),
  }));
}

function latestSnapshot(d) {
  if (!d || !d.riskLevel) return 'No riskResults/latest document.';
  return [
    `LOCKED riskLevel: ${d.riskLevel}`,
    `LOCKED performancePrediction: ${d.performancePrediction} (${d.performanceFrame || ''})`,
    `ACWR: ${d.acwr}`,
    `7-day load: ${d.trainingLoad7d}`,
    `28-day avg weekly load: ${d.trainingLoad28dAvg}`,
    `Recovery trend: ${d.recoveryTrend}`,
    `Rule-based reason: ${d.reason}`,
    `Primary recommendation: ${d.recommendation}`,
    `Recommendation status: ${d.recommendationStatus}`,
  ].join('\n');
}

function summarize(kind, judged, extra) {
  return {
    kind,
    ...extra,
    overallScore: judged.overallScore,
    overallPass: judged.overallPass,
    judgeOverallScore: judged.judgeOverallScore,
    verbosityBiasRisk: judged.verbosityBiasRisk,
    judgeSource: judged.source,
    summary: judged.summary,
    items: (judged.items || []).map((i) => ({
      id: i.id,
      pass: i.pass,
      evidence: i.evidence,
      reason: i.reason,
    })),
  };
}

async function main() {
  const key = (process.env.ANTHROPIC_API_KEY || '').trim();
  if (!key) {
    console.log(JSON.stringify({ error: 'ANTHROPIC_API_KEY missing locally' }));
    process.exit(1);
  }

  const { judgeOutput } = require('../lib/evaluation/judge');
  const athlete = await signIn(ATHLETE_EMAIL);
  const coach = await signIn(COACH_EMAIL);

  const latest = await fsGet(coach.idToken, `athletes/${athlete.uid}/riskResults/latest`);
  const d = latest.data || {};
  const chat = await fsList(
    athlete.idToken,
    `athletes/${athlete.uid}/aiChat`,
    'timestamp desc',
    30,
  );
  const traces = await fsList(
    coach.idToken,
    `athletes/${athlete.uid}/orchestratorTraces`,
    null,
    10,
  );
  traces.sort((a, b) => String(b.decidedAt || b.timestamp || '').localeCompare(String(a.decidedAt || a.timestamp || '')));
  const checkins = await fsList(
    athlete.idToken,
    `athletes/${athlete.uid}/checkins`,
    'date desc',
    14,
  );

  const results = [];

  const ai = chat.find((m) => m.isAi === true);
  const question = chat.find((m) => m.isAi !== true && m.timestamp <= (ai?.timestamp || ''))
    || chat.find((m) => m.isAi !== true);
  if (!ai) {
    results.push({ kind: 'askAthleteIQ', skipped: true, skipReason: 'No Ask AthleteIQ reply stored.' });
  } else if (ai.source === 'guard' || ai.source === 'fallback') {
    results.push({ kind: 'askAthleteIQ', skipped: true, skipReason: `Source is ${ai.source}, not llm.` });
  } else {
    const checkinLines = checkins.map((c) => {
      const load = (c.sessionDurationMinutes || 0) * (c.rpe || 0);
      return `  ${c.date || c.id}: fatigue ${c.fatigueScore}/5, sleep ${c.sleepHours ?? 'n/a'}h, load ${load}, HRV ${c.hrv ?? 'n/a'}`;
    });
    const judged = await judgeOutput({
      kind: 'askAthleteIQ',
      outputText: String(ai.text || ''),
      contextText: [
        `Athlete question: ${question?.text || '(unknown)'}`,
        latestSnapshot(d),
        'Last 14 days of check-ins:',
        ...checkinLines,
      ].join('\n'),
    });
    results.push(summarize('askAthleteIQ', judged, { generatorSource: ai.source || 'unknown' }));
  }

  const trace = traces[0];
  const orchOutput = trace
    ? JSON.stringify({ action: trace.action, orchestratorNote: trace.orchestratorNote, safetyOverride: trace.safetyOverride }, null, 2)
    : JSON.stringify({ action: d.recommendation, orchestratorNote: d.reason }, null, 2);
  const orchSource = trace?.source || d.orchestratorSource || 'unknown';
  if (!trace && !d.recommendation) {
    results.push({ kind: 'orchestrator', skipped: true, skipReason: 'No orchestrator output stored.' });
  } else if (orchSource !== 'agent' && orchSource !== 'unknown') {
    results.push({ kind: 'orchestrator', skipped: true, skipReason: `Source is ${orchSource}, not agent.` });
  } else {
    const judged = await judgeOutput({
      kind: 'orchestrator',
      outputText: orchOutput,
      contextText: latestSnapshot(d),
    });
    results.push(summarize('orchestrator', judged, { generatorSource: orchSource }));
  }

  const options = Array.isArray(d.gradedOptions) ? d.gradedOptions : [];
  const gradedSource = d.gradedOptionsSource || 'unknown';
  if (options.length === 0) {
    results.push({ kind: 'graded', skipped: true, skipReason: 'No gradedOptions stored.' });
  } else if (gradedSource !== 'llm' && gradedSource !== 'unknown') {
    results.push({ kind: 'graded', skipped: true, skipReason: `Source is ${gradedSource}, not llm.` });
  } else {
    const judged = await judgeOutput({
      kind: 'graded',
      outputText: JSON.stringify(options, null, 2),
      contextText: latestSnapshot(d),
    });
    results.push(summarize('graded', judged, { generatorSource: gradedSource }));
  }

  const explainSource = d.explanationSource || 'unknown';
  if (!d.riskLevelReasoningLLM && !d.performanceReasoningLLM) {
    results.push({ kind: 'explain', skipped: true, skipReason: 'No hybrid explanation stored.' });
  } else if (explainSource !== 'llm' && explainSource !== 'unknown') {
    results.push({ kind: 'explain', skipped: true, skipReason: `Source is ${explainSource}, not llm.` });
  } else {
    const judged = await judgeOutput({
      kind: 'explain',
      outputText: JSON.stringify({
        riskLevelReasoningLLM: d.riskLevelReasoningLLM,
        riskLevelPatternFlag: d.riskLevelPatternFlag,
        performanceReasoningLLM: d.performanceReasoningLLM,
      }, null, 2),
      contextText: latestSnapshot(d),
    });
    results.push(summarize('explain', judged, { generatorSource: explainSource }));
  }

  const researchSource = d.researchSource || 'unknown';
  if (!d.researchNote) {
    results.push({ kind: 'research', skipped: true, skipReason: 'No researchNote stored.' });
  } else if (researchSource !== 'llm' && researchSource !== 'unknown') {
    results.push({ kind: 'research', skipped: true, skipReason: `Source is ${researchSource}, not llm.` });
  } else {
    const judged = await judgeOutput({
      kind: 'research',
      outputText: JSON.stringify({ note: d.researchNote, citations: d.researchCitations || [] }, null, 2),
      contextText: latestSnapshot(d),
    });
    results.push(summarize('research', judged, { generatorSource: researchSource }));
  }

  console.log(
    JSON.stringify(
      {
        athleteUid: athlete.uid,
        athleteName: 'Alex Rivera',
        latestHttp: latest.status,
        latestRisk: d.riskLevel || null,
        keyPresent: true,
        results,
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
