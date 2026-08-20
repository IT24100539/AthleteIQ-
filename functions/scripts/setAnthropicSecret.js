/** Read ANTHROPIC_API_KEY from functions/.env and pipe to stdout only. Never logs the key. */
const fs = require('fs');
const path = require('path');

const envPath = path.join(__dirname, '..', '.env');
if (!fs.existsSync(envPath)) {
  console.error('.env missing');
  process.exit(1);
}
const raw = fs.readFileSync(envPath, 'utf8');
const line = raw.split(/\r?\n/).find((l) => l.startsWith('ANTHROPIC_API_KEY='));
if (!line) {
  console.error('ANTHROPIC_API_KEY not found in .env');
  process.exit(1);
}
let value = line.slice('ANTHROPIC_API_KEY='.length).trim();
if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
  value = value.slice(1, -1);
}
if (!value) {
  console.error('ANTHROPIC_API_KEY is empty in .env');
  process.exit(1);
}
process.stdout.write(value);
