// mosques.admin.controller.js
// =============================================================================
// Admin controller: POST /v1/mosques/:mosqueId/timings/upload
//
// Pipeline:
//   1. Validate uploaded image (type + size enforced by multer in the router)
//   2. Base64-encode the buffer and send to Gemini Vision
//   3. Parse the AI JSON response into validated time strings
//   4. Write to PrayerTiming with verificationStatus: 'pending'
//   5. Return the created record (201)
//
// Schema constraints honoured here (cross-checked against schema.prisma):
//   ✓ jumuah        — Prisma field is `jumuah` (not `jumuAh`) — camelCase of DB column
//   ✓ sourceNote    — used to record the uploading user's ID (auditable trail)
//   ✓ verifiedBy    — left null; set later by an admin verifier
//   ✗ addedById     — DOES NOT EXIST on PrayerTiming — original spec had a bug here
//
// Unique constraint:  @@unique([mosqueId, effectiveDate])
//   One timing record per mosque per day. If a record already exists, we return
//   409 Conflict instead of crashing with a P2002 Prisma error.
// =============================================================================

import prisma      from './prisma.js';
import { geminiVision } from './gemini.js';

// ---------------------------------------------------------------------------
// Allowed image MIME types — enforced here + by multer fileFilter
// ---------------------------------------------------------------------------
const ALLOWED_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
]);

// Strict OCR prompt — returned via responseMimeType: 'application/json'
// so Gemini guarantees a JSON body with no markdown wrapper.
const TIMETABLE_PROMPT = `
You are an expert OCR data extraction engine specialising in mosque prayer timetables.

Analyse the uploaded image and extract the prayer times.
Return a single JSON object with EXACTLY these keys.
Times must be in 24-hour HH:MM format (e.g. "04:32", "18:07").
If a value cannot be determined from the image, use null.

{
  "fajr":    "HH:MM",
  "sunrise": "HH:MM",
  "dhuhr":   "HH:MM",
  "asr":     "HH:MM",
  "maghrib": "HH:MM",
  "isha":    "HH:MM",
  "jumuah":  "HH:MM or null"
}

Rules:
- Return ONLY the JSON object. No explanation, no markdown, no backticks.
- Do not invent times. If a field is genuinely not visible, return null for that field.
- Fajr and Isha are always present in a valid timetable — if you cannot read them, say so with null.
`.trim();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Validates that a string is HH:MM in 24-hour format, or null/undefined. */
function isValidTime(value) {
  if (value === null || value === undefined) return true; // null is allowed for optional fields
  return typeof value === 'string' && /^\d{2}:\d{2}$/.test(value);
}

/** Validates all required fields in the AI-parsed object. */
function validateTimings(t) {
  const required = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];
  const errors   = [];

  for (const field of required) {
    if (!t[field]) {
      errors.push(`"${field}" is required but was null or missing in the AI response`);
    } else if (!isValidTime(t[field])) {
      errors.push(`"${field}" must be HH:MM format, got: ${t[field]}`);
    }
  }

  // jumuah is optional — only validate format if present
  if (t.jumuah !== null && t.jumuah !== undefined && !isValidTime(t.jumuah)) {
    errors.push(`"jumuah" must be HH:MM format or null, got: ${t.jumuah}`);
  }

  return errors;
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

export async function processTimetableImage(req, res) {
  const { mosqueId } = req.params;

  // ── Guard: GEMINI_API_KEY must be configured ────────────────────────────
  if (!process.env.GEMINI_API_KEY || process.env.GEMINI_API_KEY === 'your_actual_api_key_here') {
    return res.status(503).json({
      error: {
        code:    'SERVICE_UNAVAILABLE',
        message: 'OCR service is not configured. Set GEMINI_API_KEY in .env.',
      },
    });
  }

  // ── Step 1: Validate uploaded file ─────────────────────────────────────
  if (!req.file) {
    return res.status(400).json({
      error: { code: 'NO_FILE', message: 'No image uploaded. Send the file under the key "timetable".' },
    });
  }

  if (!ALLOWED_MIME_TYPES.has(req.file.mimetype)) {
    return res.status(415).json({
      error: {
        code:    'UNSUPPORTED_MEDIA_TYPE',
        message: `Unsupported image type: ${req.file.mimetype}. Use JPEG, PNG, WebP, or HEIC.`,
      },
    });
  }

  // ── Step 2: Confirm the mosque exists before calling the AI ─────────────
  // Saves a Gemini API credit if the mosqueId is invalid
  const mosque = await prisma.mosque.findUnique({ where: { id: mosqueId } });
  if (!mosque) {
    return res.status(404).json({
      error: { code: 'MOSQUE_NOT_FOUND', message: `Mosque ${mosqueId} not found.` },
    });
  }

  // ── Step 3: Prepare image for Gemini Vision ─────────────────────────────
  const imagePart = {
    inlineData: {
      data:     req.file.buffer.toString('base64'),
      mimeType: req.file.mimetype,
    },
  };

  // ── Step 4: Execute Gemini OCR extraction ──────────────────────────────
  let timings;
  try {
    const result       = await geminiVision.generateContent([TIMETABLE_PROMPT, imagePart]);
    const responseText = result.response.text().trim();

    // Defensive clean-up: strip markdown fences if the model ignores responseMimeType
    const cleanJson = responseText
      .replace(/^```(?:json)?\s*/i, '')
      .replace(/\s*```$/,           '');

    timings = JSON.parse(cleanJson);
  } catch (err) {
    console.error('[OCR] Gemini extraction failed:', err.message);

    if (err instanceof SyntaxError) {
      return res.status(422).json({
        error: {
          code:    'OCR_PARSE_FAILED',
          message: 'The AI returned an unparseable response. Try a clearer image.',
        },
      });
    }
    return res.status(502).json({
      error: {
        code:    'OCR_SERVICE_ERROR',
        message: 'The AI service returned an unexpected error. Please retry.',
      },
    });
  }

  // ── Step 5: Validate the parsed timings object ─────────────────────────
  const validationErrors = validateTimings(timings);
  if (validationErrors.length > 0) {
    return res.status(422).json({
      error: {
        code:    'OCR_INCOMPLETE',
        message: 'The AI could not extract all required timings. Try a clearer image.',
        details: validationErrors,
      },
    });
  }

  // ── Step 6: Persist to Postgres ────────────────────────────────────────
  // Schema field mapping (cross-checked against schema.prisma):
  //   jumuah     ← Prisma field name (DB column: jumuah)   ✓
  //   sourceNote ← records the uploader for audit trail     ✓
  //   verifiedBy ← stays null until an admin approves       ✓
  //   addedById  ← DOES NOT EXIST on PrayerTiming — removed ✗ (original bug)
  let newTiming;
  try {
    newTiming = await prisma.prayerTiming.create({
      data: {
        mosqueId,
        effectiveDate:      new Date(),
        fajr:               timings.fajr,
        sunrise:            timings.sunrise,
        dhuhr:              timings.dhuhr,
        asr:                timings.asr,
        maghrib:            timings.maghrib,
        isha:               timings.isha,
        jumuah:             timings.jumuah ?? null,  // ← correct Prisma field name
        calcMethod:         'manual',
        verificationStatus: 'pending',
        // sourceNote stores the uploader's user ID — auditable, not a FK
        sourceNote: `OCR upload by user ${req.user.id} — awaiting admin verification.`,
        // verifiedBy: null  ← default; set when an admin approves
      },
    });
  } catch (err) {
    // @@unique([mosqueId, effectiveDate]) constraint — one record per mosque per day
    if (err.code === 'P2002') {
      return res.status(409).json({
        error: {
          code:    'TIMING_ALREADY_EXISTS',
          message: `A prayer timing record already exists for mosque ${mosqueId} today. ` +
                   'Delete or update the existing record before uploading a new one.',
        },
      });
    }
    // mosqueId FK violation — mosque was deleted between our check and the insert
    if (err.code === 'P2003') {
      return res.status(404).json({
        error: { code: 'MOSQUE_NOT_FOUND', message: 'Mosque no longer exists.' },
      });
    }
    console.error('[OCR] Prisma write failed:', err);
    return res.status(500).json({
      error: { code: 'DB_WRITE_FAILED', message: 'Failed to save the extracted timings.' },
    });
  }

  // ── Step 7: Return success ─────────────────────────────────────────────
  return res.status(201).json({
    message: 'Timetable extracted successfully and is pending admin verification.',
    data:    newTiming,
  });
}

// =============================================================================
// List All Mosques (for selector in admin panel)
// =============================================================================
export async function listAllMosques(req, res) {
  try {
    const mosques = await prisma.mosque.findMany({
      orderBy: { name: 'asc' },
    });
    return res.status(200).json({ data: mosques });
  } catch (err) {
    console.error('[Admin] Failed to list mosques:', err);
    return res.status(500).json({
      error: { code: 'DB_READ_FAILED', message: 'Failed to retrieve mosques.' },
    });
  }
}

// =============================================================================
// Verify & Update Timings
// =============================================================================
export async function verifyTimings(req, res) {
  const { mosqueId, timingId } = req.params;
  const { fajr, sunrise, dhuhr, asr, maghrib, isha, jumuah } = req.body;

  // 1. Authorization guard — role must be admin or verifier
  if (req.user.role !== 'admin' && req.user.role !== 'verifier') {
    return res.status(403).json({
      error: { code: 'FORBIDDEN', message: 'Only admins or verifiers can verify timings.' },
    });
  }

  // 2. Format validation
  const timings = { fajr, sunrise, dhuhr, asr, maghrib, isha, jumuah };
  const validationErrors = validateTimings(timings);
  if (validationErrors.length > 0) {
    return res.status(422).json({
      error: {
        code:    'VALIDATION_FAILED',
        message: 'One or more prayer times have an invalid format.',
        details: validationErrors,
      },
    });
  }

  // 3. Update the record
  try {
    const timing = await prisma.prayerTiming.findUnique({
      where: { id: timingId },
    });

    if (!timing) {
      return res.status(404).json({
        error: { code: 'TIMING_NOT_FOUND', message: `Timing record ${timingId} not found.` },
      });
    }

    if (timing.mosqueId !== mosqueId) {
      return res.status(400).json({
        error: { code: 'BAD_REQUEST', message: 'Timing record does not belong to the specified mosque.' },
      });
    }

    const updatedTiming = await prisma.prayerTiming.update({
      where: { id: timingId },
      data: {
        fajr,
        sunrise,
        dhuhr,
        asr,
        maghrib,
        isha,
        jumuah: jumuah ?? null,
        verificationStatus: 'verified',
        verifiedBy: req.user.id,
        verifiedAt: new Date(),
        sourceNote: (timing.sourceNote ?? '') + ` | Verified by user ${req.user.id}.`,
      },
    });

    return res.status(200).json({
      message: 'Prayer timings verified and published successfully.',
      data:    updatedTiming,
    });
  } catch (err) {
    console.error('[Admin] Verification failed:', err);
    return res.status(500).json({
      error: { code: 'DB_WRITE_FAILED', message: 'Failed to verify and update the timings.' },
    });
  }
}
