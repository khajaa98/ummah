// generateToken.js — one-shot test token generator
// Run: node generateToken.js

import jwt from 'jsonwebtoken';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

// Manually parse .env so we don't need dotenv installed as a runtime dep
const __dirname = dirname(fileURLToPath(import.meta.url));
const envPath   = join(__dirname, '.env');
const envLines  = readFileSync(envPath, 'utf8').split('\n');
const envVars   = {};
for (const line of envLines) {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith('#')) continue;
  const [key, ...valueParts] = trimmed.split('=');
  envVars[key.trim()] = valueParts.join('=').trim().replace(/^"|"$/g, '');
}

const secret = envVars.JWT_SECRET;
if (!secret) {
  console.error('❌  JWT_SECRET not found in .env');
  process.exit(1);
}

// Use the hardcoded UUID of the Tolichowki Masjid user for the test
const payload = {
  sub:    '123e4567-e89b-12d3-a456-426614174000', // standard JWT subject claim
  role:   'admin',
  locale: 'en',
};

const token = jwt.sign(payload, secret, { expiresIn: '30d' });

console.log('\n╔══════════════════════════════════════════════════════╗');
console.log('║         BEARER TOKEN — COPY EVERYTHING BELOW         ║');
console.log('╚══════════════════════════════════════════════════════╝\n');
console.log(token);
console.log('\n══════════════════════════════════════════════════════\n');
console.log('Postman → Authorization → Bearer Token → paste above ^');
console.log(`Expires: ${new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toUTCString()}\n`);
