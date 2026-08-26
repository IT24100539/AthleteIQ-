/** List secretEnvironmentVariables on deployed Gen2 functions. Never prints secret values. */
const path = require('path');
module.paths.push(path.join(path.dirname(process.execPath), 'node_modules'));
const toolsAuth = require('firebase-tools/lib/auth');
const toolsApiv2 = require('firebase-tools/lib/apiv2');

const PROJECT = 'athleteiq-app';
const FUNCTIONS = [
  { name: 'recalculateRisk', region: 'us-central1' },
  { name: 'nightlyRecalculateRisk', region: 'us-central1' },
  { name: 'askAthleteIQ', region: 'us-central1' },
  { name: 'classifyCustomSport', region: 'us-central1' },
  { name: 'submitPainReport', region: 'us-central1' },
  { name: 'getWeeklyReport', region: 'us-central1' },
  { name: 'evaluateLlmOutput', region: 'us-central1' },
  { name: 'evaluateAthleteLlmHistory', region: 'us-central1' },
  { name: 'resyncCheckInCoachViews', region: 'us-central1' },
  { name: 'onCheckInWritten', region: 'asia-south1' },
];

async function token() {
  const account = toolsAuth.getGlobalDefaultAccount();
  if (!account?.tokens) throw new Error('firebase login required');
  toolsAuth.setActiveAccount({ project: PROJECT, projectId: PROJECT }, account);
  if (account.tokens.refresh_token) toolsApiv2.setRefreshToken(account.tokens.refresh_token);
  if (account.tokens.access_token) toolsApiv2.setAccessToken(account.tokens.access_token);
  const t = await toolsApiv2.getAccessToken();
  if (!t) throw new Error('no access token');
  return t;
}

async function describeFunction(name, region) {
  const url = `https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/${region}/functions/${name}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${await token()}` } });
  const json = await res.json();
  if (!res.ok) {
    return { name, region, error: json.error?.message || res.status };
  }
  const secrets = json.serviceConfig?.secretEnvironmentVariables ?? [];
  const anthropic = secrets.filter((s) => s.key === 'ANTHROPIC_API_KEY');
  return {
    name,
    region,
    state: json.state,
    anthropicAttached: anthropic.length > 0,
    secretKeys: secrets.map((s) => s.key),
    anthropicSecret: anthropic[0]
      ? { key: anthropic[0].key, secret: anthropic[0].secret, version: anthropic[0].version }
      : null,
  };
}

async function main() {
  const results = [];
  for (const fn of FUNCTIONS) {
    results.push(await describeFunction(fn.name, fn.region));
  }
  console.log(JSON.stringify({ project: PROJECT, functions: results }, null, 2));
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
