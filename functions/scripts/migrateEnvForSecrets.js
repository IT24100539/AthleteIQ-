/**
 * Firebase deploy rejects binding ANTHROPIC_API_KEY as a secret when the
 * same name exists in functions/.env. Move the key to .secret.local (emulator)
 * and leave only non-secret vars in .env.
 */
const fs = require('fs');
const path = require('path');

const dir = path.join(__dirname, '..');
const envPath = path.join(dir, '.env');
const secretLocalPath = path.join(dir, '.secret.local');
const examplePath = path.join(dir, '.env.example');

if (!fs.existsSync(envPath)) {
  console.error('.env missing');
  process.exit(1);
}

const raw = fs.readFileSync(envPath, 'utf8');
const lines = raw.split(/\r?\n/);
let keyValue = '';
const kept = [];

for (const line of lines) {
  if (line.startsWith('ANTHROPIC_API_KEY=')) {
    keyValue = line.slice('ANTHROPIC_API_KEY='.length).trim();
    if (
      (keyValue.startsWith('"') && keyValue.endsWith('"')) ||
      (keyValue.startsWith("'") && keyValue.endsWith("'"))
    ) {
      keyValue = keyValue.slice(1, -1);
    }
    continue;
  }
  kept.push(line);
}

if (!keyValue) {
  console.error('ANTHROPIC_API_KEY missing or empty in .env — nothing to migrate');
  process.exit(1);
}

const secretLocal = [
  '# Local emulator only — gitignored. Production uses Secret Manager.',
  `ANTHROPIC_API_KEY=${keyValue}`,
  '',
].join('\n');
fs.writeFileSync(secretLocalPath, secretLocal, 'utf8');

// Ensure .env keeps model + pointer comment, no deploy-time secret overlap.
const modelLine =
  kept.find((l) => l.startsWith('ANTHROPIC_MODEL=')) ||
  'ANTHROPIC_MODEL=claude-sonnet-5';
const newEnv = [
  '# Non-secret vars only — deploy loads this file into Cloud Functions.',
  '# ANTHROPIC_API_KEY: local → .secret.local | production → Secret Manager.',
  modelLine,
  '',
].join('\n');
fs.writeFileSync(envPath, newEnv, 'utf8');

const example = [
  '# Copy to functions/.env (non-secrets) and functions/.secret.local (API key).',
  '# Never commit either file.',
  'ANTHROPIC_MODEL=claude-sonnet-5',
  '',
  '# functions/.secret.local (emulator):',
  '# ANTHROPIC_API_KEY=sk-ant-...',
  '',
  '# Production:',
  '# firebase functions:secrets:set ANTHROPIC_API_KEY',
  '',
].join('\n');
fs.writeFileSync(examplePath, example, 'utf8');

console.log(
  JSON.stringify({
    migratedKeyTo: '.secret.local',
    envNowContains: ['ANTHROPIC_MODEL'],
    keyLength: keyValue.length,
  }),
);
