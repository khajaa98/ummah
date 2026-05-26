// src/lib/redis.js
// =============================================================================
// Redis client singleton — IORedis with explicit GEO helper wrappers.
// All mosque GEO operations are funnelled through this module so the key
// naming convention is enforced in one place.
// =============================================================================

import Redis from 'ioredis';

const redis = new Redis({
  host:     process.env.REDIS_HOST     || '127.0.0.1',
  port:     parseInt(process.env.REDIS_PORT || '6379', 10),
  password: process.env.REDIS_PASSWORD || undefined,
  db:       parseInt(process.env.REDIS_DB   || '0',    10),
  // Reconnect with bounded exponential back-off (max 10 s)
  retryStrategy: (times) => Math.min(times * 200, 10_000),
  enableReadyCheck: true,
  maxRetriesPerRequest: 3,
});

redis.on('error',   (err) => console.error('[Redis] connection error:', err));
redis.on('connect', ()    => console.info ('[Redis] connected'));

// ---------------------------------------------------------------------------
// Key constants
// ---------------------------------------------------------------------------

export const GEO_KEY     = 'mosques:geo';           // ZSET backing GEORADIUS
export const META_PREFIX = 'mosques:meta:';         // HASH per mosque

// ---------------------------------------------------------------------------
// GEO helpers
// ---------------------------------------------------------------------------

/**
 * Add or update a mosque in the Redis GEO index.
 * Called from the Mosque create/update controller.
 *
 * @param {string} mosqueId  - UUID
 * @param {number} longitude - WGS-84
 * @param {number} latitude  - WGS-84
 */
export async function geoAddMosque(mosqueId, longitude, latitude) {
  return redis.geoadd(GEO_KEY, longitude, latitude, mosqueId);
}

/**
 * Remove a mosque from the GEO index (e.g. status → 'closed').
 *
 * @param {string} mosqueId
 */
export async function geoRemoveMosque(mosqueId) {
  return redis.zrem(GEO_KEY, mosqueId);
}

/**
 * Query mosques within a radius of a coordinate pair.
 * Raw client coords exist only in this function's scope — never serialised.
 *
 * @param {number} latitude
 * @param {number} longitude
 * @param {number} radiusKm
 * @param {number} limit
 * @returns {Promise<Array<{mosqueId: string, distanceKm: string, coordinates: [string,string]}>>}
 */
export async function geoRadiusQuery(latitude, longitude, radiusKm, limit) {
  // GEORADIUS <key> <lng> <lat> <radius> km WITHCOORD WITHDIST COUNT <n> ASC
  const raw = await redis.georadius(
    GEO_KEY,
    longitude,
    latitude,
    radiusKm,
    'km',
    'WITHCOORD',
    'WITHDIST',
    'COUNT', limit,
    'ASC',
  );

  // IORedis returns: [ [memberId, distStr, [lngStr, latStr]], ... ]
  return raw.map(([mosqueId, distanceKm, [lng, lat]]) => ({
    mosqueId,
    distanceKm,
    coordinates: { latitude: parseFloat(lat), longitude: parseFloat(lng) },
  }));
}

/**
 * Write or refresh denormalised mosque metadata into a Redis HASH.
 * Used to avoid a Postgres round-trip on every nearby query.
 *
 * @param {string} mosqueId
 * @param {object} meta - { name, nameAr, madhab, status, city, countryCode }
 */
export async function setMosqueMeta(mosqueId, meta) {
  const key = META_PREFIX + mosqueId;
  return redis.hset(key, {
    name:        meta.name        || '',
    name_ar:     meta.nameAr      || '',
    madhab:      meta.madhab      || '',
    status:      meta.status      || '',
    city:        meta.city        || '',
    country_code: meta.countryCode || '',
  });
}

/**
 * Fetch denormalised metadata for a list of mosque IDs.
 * Uses a pipeline to batch all HGETALL calls in one round-trip.
 *
 * @param {string[]} mosqueIds
 * @returns {Promise<Map<string, object>>}
 */
export async function getMosqueMetas(mosqueIds) {
  if (!mosqueIds.length) return new Map();

  const pipeline = redis.pipeline();
  for (const id of mosqueIds) {
    pipeline.hgetall(META_PREFIX + id);
  }
  const results = await pipeline.exec();

  const map = new Map();
  results.forEach(([err, data], i) => {
    if (!err && data && Object.keys(data).length) {
      map.set(mosqueIds[i], data);
    }
  });
  return map;
}

export default redis;
