/** Print whether athleteiq-app has a billing account. Never logs tokens. */
const path = require('path');
module.paths.push(path.join(path.dirname(process.execPath), 'node_modules'));
const toolsAuth = require('firebase-tools/lib/auth');
const toolsApiv2 = require('firebase-tools/lib/apiv2');

const PROJECT = 'athleteiq-app';

async function token() {
  const account = toolsAuth.getGlobalDefaultAccount();
  if (!account?.tokens) throw new Error('firebase login required');
  toolsAuth.setActiveAccount({ project: PROJECT, projectId: PROJECT }, account);
  if (account.tokens.refresh_token) toolsApiv2.setRefreshToken(account.tokens.refresh_token);
  if (account.tokens.access_token) toolsApiv2.setAccessToken(account.tokens.access_token);
  const t = await toolsApiv2.getAccessToken();
  if (!t) throw new Error('no token');
  return t;
}

async function main() {
  const t = await token();
  const headers = { Authorization: `Bearer ${t}` };
  const billing = await fetch(
    `https://cloudbilling.googleapis.com/v1/projects/${PROJECT}/billingInfo`,
    { headers },
  ).then((r) => r.json());
  const firebase = await fetch(
    `https://firebase.googleapis.com/v1beta1/projects/${PROJECT}`,
    { headers },
  ).then((r) => r.json());
  console.log(
    JSON.stringify(
      {
        billingEnabled: billing.billingEnabled === true,
        billingAccountName: billing.billingAccountName ? '(set)' : null,
        firebaseDisplayName: firebase.displayName,
        state: firebase.state,
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
