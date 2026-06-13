// mosques.search.controller.js
// =============================================================================
// Controller: GET /v1/mosques/search?q=balkampet&limit=20
//
// Text-based mosque search — used when the user denies location permission
// and falls back to manual city/name search. Searches by name, nameAr, and
// city using a case-insensitive LIKE query. Returns the same shape as the
// /nearby endpoint so the Flutter MosqueCard widget renders identically.
// =============================================================================

import prisma from './prisma.js';

/**
 * GET /v1/mosques/search
 *
 * Query params:
 *   q     (required) — search string, min 2 chars
 *   limit (optional) — max results, default 20
 */
export async function searchMosques(req, res) {
  const { q, limit: limitRaw } = req.query;

  if (!q || q.trim().length < 2) {
    return res.status(400).json({
      error: {
        code:    'INVALID_PARAMS',
        message: 'Query param "q" must be at least 2 characters.',
      },
    });
  }

  const limit = Math.min(parseInt(limitRaw ?? '20', 10) || 20, 100);
  const term  = q.trim();

  const mosques = await prisma.mosque.findMany({
    where: {
      status: 'active',
      OR: [
        { name:   { contains: term, mode: 'insensitive' } },
        { nameAr: { contains: term, mode: 'insensitive' } },
        { city:   { contains: term, mode: 'insensitive' } },
      ],
    },
    select: {
      id:          true,
      name:        true,
      nameAr:      true,
      latitude:    true,
      longitude:   true,
      addressLine: true,
      city:        true,
      madhab:      true,
      status:      true,
      prayerTimings: {
        where:   { verificationStatus: 'verified', effectiveDate: { gte: new Date() } },
        select:  { id: true },
        take:    1,
      },
      checkIns: {
        where: {
          checkedInAt: {
            gte: new Date(new Date().toISOString().slice(0, 10) + 'T00:00:00.000Z'),
            lte: new Date(new Date().toISOString().slice(0, 10) + 'T23:59:59.999Z'),
          },
        },
        select: { id: true },
      },
    },
    take: limit,
    orderBy: { name: 'asc' },
  });

  const data = mosques.map((m) => ({
    id:                   m.id,
    name:                 m.name,
    name_ar:              m.nameAr ?? null,
    distance_km:          0,       // not GPS-based — client can show "Search result"
    address_line:         m.addressLine ?? null,
    city:                 m.city,
    madhab:               m.madhab,
    status:               m.status,
    coordinates: {
      latitude:  m.latitude,
      longitude: m.longitude,
    },
    has_verified_timings: m.prayerTimings.length > 0,
    checkin_count_today:  m.checkIns.length,
  }));

  return res.status(200).json({
    data,
    meta: { total: data.length, query: term },
  });
}
