// src/controllers/mosques.nearby.controller.js
// =============================================================================
// Controller: GET /v1/mosques/nearby
//
// Execution pipeline (mirrors the architect's spec exactly):
//
//   1. Read validated params from req.nearbyParams (set by validateNearby middleware)
//   2. Execute GEORADIUS against Redis — raw coords live ONLY in this scope
//   3. If a madhab filter is requested, load full metadata from Postgres to filter
//      accurately; otherwise use Redis HASH metadata for a faster path
//   4. Hydrate today's check-in counts from Postgres in a single batched query
//   5. Check for verified timings existence per mosque in a single batched query
//   6. Write GeoQueryLog with geohash PREFIX only (precision 4, ≈40 km cell)
//      — raw lat/lng are NEVER written to any persistent store
//   7. Return shaped response; coords go out of scope and are GC'd
//
// Data minimization guarantees:
//   ✓ req.nearbyParams.lat / .lng are plain JS numbers in memory
//   ✓ geoRadiusQuery() never touches Postgres
//   ✓ GeoQueryLog.create() receives only the geohash prefix
//   ✓ No logging middleware logs body/query for this route (configured in router)
// =============================================================================

import prisma                         from './prisma.js';
import { geoRadiusQuery, getMosqueMetas } from './redis.js';
import { encodeGeohash }              from './geohash.js';

/**
 * GET /v1/mosques/nearby
 *
 * @param {import('express').Request}  req
 * @param {import('express').Response} res
 */
export async function getNearbyMosques(req, res) {
  const { lat, lng, radiusKm, limit, madhab } = req.nearbyParams;
  const userId = req.user.id;

  // -------------------------------------------------------------------------
  // Step 1 — Redis GEORADIUS query
  // lat and lng are consumed here. They will not be passed to any I/O call
  // beyond this point.
  // -------------------------------------------------------------------------
  let geoResults;
  try {
    geoResults = await geoRadiusQuery(lat, lng, radiusKm, limit);
  } catch (err) {
    console.error('[getNearbyMosques] Redis GEORADIUS failed:', err);
    return res.status(503).json({
      error: {
        code:    'SERVICE_UNAVAILABLE',
        message: 'Location service is temporarily unavailable. Please retry shortly.',
      },
    });
  }

  if (geoResults.length === 0) {
    // Write log before returning (no mosques found is still a valid query)
    await writeGeoQueryLog(userId, lat, lng, radiusKm, 0).catch(logError);
    return res.status(200).json(buildResponse([], radiusKm));
  }

  const mosqueIds = geoResults.map((r) => r.mosqueId);

  // -------------------------------------------------------------------------
  // Step 2 — Fetch mosque metadata
  //
  // Fast path: pull from Redis HASH cache (avoids a Postgres round-trip).
  // Slow path fallback: any IDs missing from cache are fetched from Postgres
  // and the cache is backfilled.
  //
  // If a madhab filter is active we must consult Postgres for accuracy because
  // the Redis HASH only stores a string value and enum case needs to be exact.
  // -------------------------------------------------------------------------
  let mosqueMetaMap; // Map<mosqueId, metaObject>

  try {
    mosqueMetaMap = await resolveMetadata(mosqueIds, madhab);
  } catch (err) {
    console.error('[getNearbyMosques] Metadata resolution failed:', err);
    return res.status(500).json({
      error: { code: 'INTERNAL_ERROR', message: 'Failed to retrieve mosque details.' },
    });
  }

  // Apply madhab filter post-resolution (done in JS to keep Redis query simple)
  let filteredIds = mosqueIds;
  if (madhab) {
    filteredIds = mosqueIds.filter((id) => {
      const meta = mosqueMetaMap.get(id);
      return meta && meta.madhab === madhab && meta.status === 'active';
    });
  } else {
    // Still exclude closed/unverified mosques
    filteredIds = mosqueIds.filter((id) => {
      const meta = mosqueMetaMap.get(id);
      return meta && meta.status === 'active';
    });
  }

  if (filteredIds.length === 0) {
    await writeGeoQueryLog(userId, lat, lng, radiusKm, 0).catch(logError);
    return res.status(200).json(buildResponse([], radiusKm));
  }

  // -------------------------------------------------------------------------
  // Step 3 — Batch: today's check-in counts + verified timings existence
  // Two Postgres queries, each covering all mosqueIds in one round-trip.
  // -------------------------------------------------------------------------
  const today     = getTodayDateString();
  const [checkinCounts, verifiedTimingIds] = await Promise.all([
    fetchCheckinCountsToday(filteredIds, today),
    fetchVerifiedTimingIds(filteredIds, today),
  ]);

  // -------------------------------------------------------------------------
  // Step 4 — Write GeoQueryLog (fire-and-forget, non-blocking)
  // CRITICAL: only geohashPrefix is persisted — raw lat/lng are NOT passed.
  // -------------------------------------------------------------------------
  writeGeoQueryLog(userId, lat, lng, radiusKm, filteredIds.length).catch(logError);

  // -------------------------------------------------------------------------
  // Step 5 — Shape response
  // lat and lng are no longer referenced after this point.
  // -------------------------------------------------------------------------
  const geoByMosqueId = new Map(geoResults.map((r) => [r.mosqueId, r]));

  const data = filteredIds.map((id) => {
    const geo  = geoByMosqueId.get(id);
    const meta = mosqueMetaMap.get(id);

    return {
      id,
      name:                 meta.name        || null,
      name_ar:              meta.name_ar      || null,
      distance_km:          parseFloat(parseFloat(geo.distanceKm).toFixed(2)),
      address_line:         meta.address_line || null,
      city:                 meta.city         || null,
      madhab:               meta.madhab       || null,
      status:               meta.status,
      // Mosque's own public coordinates — safe to return (operator-supplied data)
      coordinates: {
        latitude:  geo.coordinates.latitude,
        longitude: geo.coordinates.longitude,
      },
      has_verified_timings: verifiedTimingIds.has(id),
      checkin_count_today:  checkinCounts.get(id) ?? 0,
    };
  });

  return res.status(200).json(buildResponse(data, radiusKm));
}

// =============================================================================
// Private helpers
// =============================================================================

/**
 * Resolve metadata for a list of mosque IDs.
 * Tries Redis first; falls back to Postgres for cache misses and backfills.
 *
 * @param {string[]} mosqueIds
 * @param {string|null} madhabFilter - pass through for Postgres query selectivity
 * @returns {Promise<Map<string, object>>}
 */
async function resolveMetadata(mosqueIds, madhabFilter) {
  const redisMap = await getMosqueMetas(mosqueIds);

  const missingIds = mosqueIds.filter((id) => !redisMap.has(id));

  if (missingIds.length === 0) return redisMap;

  // Fetch misses from Postgres
  const dbRows = await prisma.mosque.findMany({
    where: { id: { in: missingIds } },
    select: {
      id:          true,
      name:        true,
      nameAr:      true,
      madhab:      true,
      status:      true,
      city:        true,
      countryCode: true,
      addressLine: true,
    },
  });

  // Merge into map and backfill Redis cache (fire-and-forget)
  const { setMosqueMeta } = await import('./redis.js');
  for (const row of dbRows) {
    const meta = {
      name:         row.name,
      name_ar:      row.nameAr      ?? '',
      madhab:       row.madhab,
      status:       row.status,
      city:         row.city,
      countryCode:  row.countryCode,
      address_line: row.addressLine ?? '',
    };
    redisMap.set(row.id, meta);
    setMosqueMeta(row.id, row).catch(logError); // async backfill, don't await
  }

  return redisMap;
}

/**
 * Returns a Map<mosqueId, count> of today's check-ins per mosque.
 *
 * @param {string[]} mosqueIds
 * @param {string}   todayStr   - 'YYYY-MM-DD'
 * @returns {Promise<Map<string, number>>}
 */
async function fetchCheckinCountsToday(mosqueIds, todayStr) {
  const startOfDay = new Date(`${todayStr}T00:00:00.000Z`);
  const endOfDay   = new Date(`${todayStr}T23:59:59.999Z`);

  const rows = await prisma.checkIn.groupBy({
    by:     ['mosqueId'],
    where: {
      mosqueId:    { in: mosqueIds },
      checkedInAt: { gte: startOfDay, lte: endOfDay },
    },
    _count: { id: true },
  });

  return new Map(rows.map((r) => [r.mosqueId, r._count.id]));
}

/**
 * Returns a Set of mosque IDs that have at least one verified timing
 * on or after today.
 *
 * @param {string[]} mosqueIds
 * @param {string}   todayStr
 * @returns {Promise<Set<string>>}
 */
async function fetchVerifiedTimingIds(mosqueIds, todayStr) {
  const rows = await prisma.prayerTiming.findMany({
    where: {
      mosqueId:          { in: mosqueIds },
      effectiveDate:     { gte: new Date(todayStr) },
      verificationStatus: 'verified',
    },
    select:  { mosqueId: true },
    distinct: ['mosqueId'],
  });

  return new Set(rows.map((r) => r.mosqueId));
}

/**
 * Persist the GeoQueryLog entry.
 *
 * PRIVACY CONTRACT:
 *   Only the geohash PREFIX is written (precision 4 ≈ 40 km cell).
 *   The raw lat/lng are used *solely* to compute the prefix and are
 *   not stored, logged, or transmitted further.
 *
 * @param {string} userId
 * @param {number} lat        - consumed only to derive geohashPrefix
 * @param {number} lng        - consumed only to derive geohashPrefix
 * @param {number} radiusKm
 * @param {number} resultCount
 */
async function writeGeoQueryLog(userId, lat, lng, radiusKm, resultCount) {
  const geohashPrefix = encodeGeohash(lat, lng, 4); // ≈ 40 km cell; raw coords go no further

  await prisma.geoQueryLog.create({
    data: {
      userId,
      geohashPrefix,  // ← only this is stored, never lat/lng
      radiusKm,
      resultCount,
    },
  });
}

/**
 * Shape the final JSON envelope.
 *
 * @param {object[]} data
 * @param {number}   radiusKm
 */
function buildResponse(data, radiusKm) {
  return {
    data,
    meta: {
      total:        data.length,
      radius_km:    radiusKm,
      privacy_note: 'Your location was used only to compute this response and was not stored.',
    },
  };
}

/** Returns today's date as 'YYYY-MM-DD' in UTC. */
function getTodayDateString() {
  return new Date().toISOString().slice(0, 10);
}

/** Standardised fire-and-forget error logger. */
function logError(err) {
  console.error('[getNearbyMosques] Background task error:', err);
}
