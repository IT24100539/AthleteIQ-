/**
 * Production E2–E5 audit. Calls live Cloud Functions, then reads
 * riskResults/latest + orchestratorTraces. Never prints tokens or keys.
 */
const WEB_KEY = 'AIzaSyDC_i4tdqWuUy8pVshNz8c0W27gOK-0lNQ';
const PROJECT = 'athleteiq-app';
const ATHLETE_EMAIL = 'demo.athlete@athleteiq.app';
const COACH_EMAIL = 'demo.coach@athleteiq.app';
const PASSWORD = 'Demo1234!';

const FALLBACK_FATIGUE =
  "I don't have a live model answer right now. Check your latest risk result " +
  'and recent sleep/fatigue logs — that combination is usually why fatigue and risk go up.';
const DEFAULT_NOTE_HIGH =
  'ACWR is a useful spike signal, not a perfect one — the 1.5 danger cutoff is contested in the literature and is one input among several, not treated as absolute truth.';
const DEFAULT_NOTE_OTHER =
  'This call is grounded in session-RPE training load, ACWR, and a simplified Banister Fitness–Fatigue read of the same series — models, not lab tests.';
const GRADED_TEMPLATE_REASONS = [
  'Highest risk tier — maximum load reduction.',
  'Partial cut if the athlete must stay active this week.',
  'Smallest adjustment that still respects elevated risk.',
  'Play it safe if signals worsen overnight.',
  'Matches the primary risk call — reduce intensity, keep volume.',
  'Lightest touch that still acknowledges mixed signals.',
];

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
  if (!json.idToken) throw new Error(`Sign-in failed: ${json.error?.message}`);
  return { idToken: json.idToken, uid: json.localId };
}

function callableUrl(name) {
  return `https://us-central1-${PROJECT}.cloudfunctions.net/${name}`;
}

async function callFn(token, name, data) {
  const res = await fetch(callableUrl(name), {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ data }),
  });
  const json = await res.json();
  return { http: res.status, body: json };
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

async function fsList(token, rel, pageSize = 5) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${rel}?pageSize=${pageSize}&orderBy=decidedAt%20desc`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  const json = await res.json();
  const docs = json.documents || [];
  return docs.map((d) => ({
    id: d.name.split('/').pop(),
    ...fromFields(d.fields),
  }));
}

async function main() {
  const athlete = await signIn(ATHLETE_EMAIL);
  const coach = await signIn(COACH_EMAIL);
  const question = 'Why am I so tired this week? What do my latest sleep, fatigue, and load numbers actually show?';

  const ask = await callFn(athlete.idToken, 'askAthleteIQ', {
    athleteUid: athlete.uid,
    question,
  });
  const askResult = ask.body.result ?? ask.body;
  const askText = askResult.text ?? '';
  const askSource = askResult.source ?? null;

  const rec = await callFn(athlete.idToken, 'recalculateRisk', {
    athleteUid: athlete.uid,
  });
  const recResult = rec.body.result ?? rec.body;

  // Pipeline can take a while; latest is written before the callable returns.
  // Pending latest is coach-only; athleteView strips LLM internals.
  const latest = await fsGet(
    coach.idToken,
    `athletes/${athlete.uid}/riskResults/latest`,
  );
  const d = latest.data || {};

  let traces = [];
  try {
    traces = await fsList(coach.idToken, `athletes/${athlete.uid}/orchestratorTraces`, 3);
  } catch (err) {
    traces = [{ error: String(err.message || err) }];
  }

  const ruleReason = typeof d.reason === 'string' ? d.reason : '';
  const llmReason = typeof d.riskLevelReasoningLLM === 'string' ? d.riskLevelReasoningLLM : '';
  const researchNote = typeof d.researchNote === 'string' ? d.researchNote : '';
  const options = Array.isArray(d.gradedOptions) ? d.gradedOptions : [];
  const optionReasons = options.map((o) => o.reason);
  const matchesGradedTemplates = optionReasons.every((r) => GRADED_TEMPLATE_REASONS.includes(r));

  const report = {
    athleteUid: athlete.uid,
    askAthleteIQ: {
      http: ask.http,
      question,
      source: askSource,
      text: askText,
      matchesFallbackAnswer: askText === FALLBACK_FATIGUE,
    },
    recalculateRisk: { http: rec.http, result: recResult },
    latestHttp: latest.status,
    latest: {
      riskLevel: d.riskLevel,
      acwr: d.acwr,
      performancePrediction: d.performancePrediction,
      performanceFrame: d.performanceFrame,
      recoveryTrend: d.recoveryTrend,
      recommendation: d.recommendation,
      orchestratorSource: d.orchestratorSource,
      orchestratorSafetyOverride: d.orchestratorSafetyOverride,
      orchestratorAgreedWithRules: d.orchestratorAgreedWithRules,
      ruleBasedRecommendation: d.ruleBasedRecommendation,
      conflict: d.orchestratorConflict,
      explanationSource: d.explanationSource,
      reason: d.reason,
      riskLevelReasoningLLM: d.riskLevelReasoningLLM,
      performanceReasoningLLM: d.performanceReasoningLLM,
      riskLevelPatternFlag: d.riskLevelPatternFlag,
      copiesRuleReason: llmReason === ruleReason,
      llmLongerThanReason: llmReason.length > ruleReason.length,
      researchSource: d.researchSource,
      researchNote: d.researchNote,
      researchCitations: d.researchCitations,
      noteEqualsDefaultNote:
        researchNote === DEFAULT_NOTE_HIGH || researchNote === DEFAULT_NOTE_OTHER,
      gradedOptionsSource: d.gradedOptionsSource,
      gradedOptions: d.gradedOptions,
      matchesGradedTemplates,
      calculatedAt: d.calculatedAt,
    },
    traces: traces.map((t) => ({
      id: t.id,
      decidedAt: t.decidedAt,
      source: t.source,
      action: t.action,
      safetyOverride: t.safetyOverride,
      agreedWithRules: t.agreedWithRules,
      trace: t.trace,
    })),
  };

  console.log(JSON.stringify(report, null, 2));
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
