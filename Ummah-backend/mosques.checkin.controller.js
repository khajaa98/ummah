// mosques.checkin.controller.js
// =============================================================================
// Controller: POST /v1/mosques/:mosqueId/checkin
//
// Records a user's attendance at a mosque for a specific prayer slot.
// Enforces one check-in per user per prayer per mosque per day.
// Returns the updated community check-in count for the day.
// =============================================================================

import prisma from './prisma.js';

const VALID_SLOTS = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha', 'jumuah'];

/**
 * POST /v1/mosques/:mosqueId/checkin
 *
 * Body: { prayer_slot: string, is_anonymous?: boolean }
 */
export async function checkInAtMosque(req, res) {
  const { mosqueId } = req.params;
  const userId       = req.user.id;
  const { prayer_slot, is_anonymous = false } = req.body ?? {};

  // ── Validate prayer_slot ──────────────────────────────────────────────────
  if (!prayer_slot || !VALID_SLOTS.includes(prayer_slot)) {
    return res.status(400).json({
      error: {
        code:    'INVALID_SLOT',
        message: `prayer_slot must be one of: ${VALID_SLOTS.join(', ')}.`,
      },
    });
  }

  // ── Verify mosque is active ───────────────────────────────────────────────
  const mosque = await prisma.mosque.findUnique({
    where:  { id: mosqueId },
    select: { id: true, status: true },
  });

  if (!mosque || mosque.status !== 'active') {
    return res.status(404).json({
      error: { code: 'NOT_FOUND', message: 'Mosque not found or not active.' },
    });
  }

  // ── Idempotency: one check-in per user per prayer per mosque per day ──────
  const today      = new Date().toISOString().slice(0, 10);
  const startOfDay = new Date(`${today}T00:00:00.000Z`);
  const endOfDay   = new Date(`${today}T23:59:59.999Z`);

  const existing = await prisma.checkIn.findFirst({
    where: {
      userId,
      mosqueId,
      prayerSlot:  prayer_slot,
      checkedInAt: { gte: startOfDay, lte: endOfDay },
    },
  });

  if (existing) {
    // 409 with current count — client can still read the count
    const count = await getTodayCount(mosqueId, startOfDay, endOfDay);
    return res.status(409).json({
      error: {
        code:               'ALREADY_CHECKED_IN',
        message:            'Already checked in for this prayer today.',
        checkin_count_today: count,
      },
    });
  }

  // ── Record check-in ───────────────────────────────────────────────────────
  const checkIn = await prisma.checkIn.create({
    data: {
      userId,
      mosqueId,
      prayerSlot:  prayer_slot,
      isAnonymous: Boolean(is_anonymous),
    },
  });

  const count = await getTodayCount(mosqueId, startOfDay, endOfDay);

  return res.status(201).json({
    data: {
      check_in_id:         checkIn.id,
      mosque_id:           mosqueId,
      prayer_slot,
      checkin_count_today: count,
    },
  });
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

async function getTodayCount(mosqueId, startOfDay, endOfDay) {
  return prisma.checkIn.count({
    where: {
      mosqueId,
      checkedInAt: { gte: startOfDay, lte: endOfDay },
    },
  });
}
