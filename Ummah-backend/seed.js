// seed.js  — corrected for flat file layout + exact Prisma field names
// =============================================================================
// Seeds 3 Hyderabad mosques into Postgres AND registers them in Redis GEO.
// Depends on seedUser.js having been run first (addedBy FK references that user).
//
// Corrections vs. original:
//   - Uses our flat ./prisma.js singleton instead of new PrismaClient()
//   - Uses ioredis (same client as the app) instead of the node-redis createClient
//   - All Prisma field names are camelCase to match schema.prisma
//   - Added required fields: madhab (enum), addedBy (FK → test user)
//   - Removed snake_case fields: address_line, country_code, status (raw string)
//   - Idempotent: skips mosques that already exist by name to allow re-runs
// =============================================================================

import prisma from './prisma.js';
import Redis  from 'ioredis';

const ADDED_BY_USER_ID = '123e4567-e89b-12d3-a456-426614174000'; // seeded by seedUser.js
const GEO_KEY          = 'mosques:geo';

const mosquesToSeed = [
  {
    name:        'Tolichowki Masjid',
    lat:         17.3984,
    lng:         78.4136,
    addressLine: 'Tolichowki X Roads',
    madhab:      'Hanafi',
  },
  {
    name:        'Mehdipatnam Grand Masjid',
    lat:         17.3931,
    lng:         78.4326,
    addressLine: 'Mehdipatnam Ring Road',
    madhab:      'Hanafi',
  },
  {
    name:        'Balkampet Center Masjid',
    lat:         17.4483,
    lng:         78.4452,
    addressLine: 'Balkampet Main Road',
    madhab:      'Hanafi',
  },
];

async function main() {
  // Connect to Redis using ioredis (same config as the app)
  const redis = new Redis({
    host:     process.env.REDIS_HOST     || '127.0.0.1',
    port:     parseInt(process.env.REDIS_PORT || '6379', 10),
    password: process.env.REDIS_PASSWORD || undefined,
    db:       parseInt(process.env.REDIS_DB   || '0',    10),
  });

  redis.on('error', (err) => console.error('[Redis]', err.message));
  console.log('\n[seed] Connected to Redis.');
  console.log('[seed] Seeding Hyderabad mosques to Postgres + Redis GEO...\n');

  let seeded = 0;
  let skipped = 0;

  for (const m of mosquesToSeed) {
    // Idempotent check — skip if mosque with this name already exists
    const existing = await prisma.mosque.findFirst({ where: { name: m.name } });
    if (existing) {
      console.log(`  ⚠️   SKIP  ${m.name} — already in Postgres (id: ${existing.id})`);

      // Still ensure it's in Redis GEO (in case Redis was flushed)
      await redis.geoadd(GEO_KEY, m.lng, m.lat, existing.id);
      console.log(`         ↳  Refreshed Redis GEO entry.`);
      skipped++;
      continue;
    }

    // Insert into Postgres — all field names are Prisma camelCase
    const mosque = await prisma.mosque.create({
      data: {
        name:        m.name,
        latitude:    m.lat,
        longitude:   m.lng,
        addressLine: m.addressLine,   // maps to address_line column
        city:        'Hyderabad',
        countryCode: 'IN',            // maps to country_code column (Char(2))
        madhab:      m.madhab,        // Madhab enum — required, non-nullable
        status:      'active',        // MosqueStatus enum
        addedBy:     ADDED_BY_USER_ID, // FK → users.id — required, non-nullable
      },
    });

    // Register in Redis GEO index — key matches GEO_KEY in redis.js
    await redis.geoadd(GEO_KEY, m.lng, m.lat, mosque.id);

    console.log(`  ✅  SEEDED ${mosque.name}`);
    console.log(`       id:      ${mosque.id}`);
    console.log(`       coords:  (${m.lat}, ${m.lng})`);
    console.log(`       madhab:  ${mosque.madhab}\n`);
    seeded++;
  }

  redis.disconnect();

  console.log(`╔══════════════════════════════════════════════╗`);
  console.log(`║            SEEDING COMPLETE                  ║`);
  console.log(`╚══════════════════════════════════════════════╝`);
  console.log(`  Seeded:  ${seeded} mosque(s)`);
  console.log(`  Skipped: ${skipped} (already existed)\n`);
  console.log(`  🕌  Redis GEO key: "${GEO_KEY}"`);
  console.log(`  📡  Now hit: GET /v1/mosques/nearby?lat=17.3984&lng=78.4136&radius_km=10&limit=5\n`);
}

main()
  .catch((err) => {
    console.error('\n[seed] ❌  Seeding failed:', err.message);
    if (err.code === 'P2003') {
      console.error('  → Foreign key violation. Did you run seedUser.js first?');
    }
    if (err.code === 'P1001') {
      console.error('  → Cannot reach Postgres. Run: docker-compose up -d');
    }
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());