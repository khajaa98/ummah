// mosques.timings.controller.js
// =============================================================================
// Controller: GET /v1/mosques/:mosqueId/timings
//
// Returns verified prayer timings for a mosque, shaped to match the Flutter
// PrayerTiming model exactly. Defaults to today + next 30 days.
//
// Query params:
//   date (optional) — 'YYYY-MM-DD' fetch a single day
//   from / to       — 'YYYY-MM-DD' date range (both required if either present)
// =============================================================================

import prisma from './prisma.js';

/**
 * GET /v1/mosques/:mosqueId/timings
 */
export async function getMosqueTimings(req, res) {
  const { mosqueId } = req.params;
  const { date, from, to } = req.query;

  // Validate mutual dependency: from and to must both be present or both absent
  if ((from && !to) || (!from && to)) {
    return res.status(400).json({
      error: {
        code:    'INVALID_PARAMS',
        message: 'Query params "from" and "to" must both be provided together.',
      },
    });
  }

  // ── Fetch mosque metadata ─────────────────────────────────────────────────
  const mosque = await prisma.mosque.findUnique({
    where:  { id: mosqueId },
    select: {
      id:          true,
      name:        true,
      nameAr:      true,
      madhab:      true,
      city:        true,
      countryCode: true,
      status:      true,
    },
  });

  if (!mosque || mosque.status === 'closed') {
    return res.status(404).json({
      error: { code: 'NOT_FOUND', message: 'Mosque not found.' },
    });
  }

  // ── Build date filter ─────────────────────────────────────────────────────
  const today     = new Date().toISOString().slice(0, 10);
  let dateFilter;

  if (date) {
    const d = new Date(date);
    dateFilter = { gte: d, lte: d };
  } else if (from && to) {
    dateFilter = { gte: new Date(from), lte: new Date(to) };
  } else {
    // Default: today through next 30 days
    const future = new Date(today);
    future.setDate(future.getDate() + 30);
    dateFilter = { gte: new Date(today), lte: future };
  }

  // ── Fetch timings ─────────────────────────────────────────────────────────
  const timings = await prisma.prayerTiming.findMany({
    where: {
      mosqueId,
      effectiveDate:      dateFilter,
      verificationStatus: 'verified',
    },
    include: {
      verifiedByUser: { select: { displayName: true } },
    },
    orderBy: { effectiveDate: 'asc' },
    take:    90,
  });

  // ── Shape response to match Flutter PrayerTiming.fromJson ─────────────────
  const shaped = timings.map((t) => ({
    effective_date: t.effectiveDate.toISOString().slice(0, 10),
    fajr:           t.fajr,
    sunrise:        t.sunrise,
    dhuhr:          t.dhuhr,
    asr:            t.asr,
    maghrib:        t.maghrib,
    isha:           t.isha,
    jumu_ah:        t.jumuah ?? null,
    calc_method:    t.calcMethod,
    verification: {
      status:              t.verificationStatus,
      verified_at:         t.verifiedAt?.toISOString() ?? null,
      verified_by_display: t.verifiedByUser?.displayName ?? null,
      source_note:         t.sourceNote ?? null,
    },
  }));

  return res.status(200).json({
    data: {
      mosque: {
        id:           mosque.id,
        name:         mosque.name,
        name_ar:      mosque.nameAr ?? null,
        madhab:       mosque.madhab,
        city:         mosque.city,
        country_code: mosque.countryCode,
      },
      timings: shaped,
    },
  });
}
