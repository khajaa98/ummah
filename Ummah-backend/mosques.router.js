// mosques.router.js
// =============================================================================
// Mosque resource router — mounted at /v1/mosques in app.js
//
// Routes:
//
//   GET  /nearby
//     1. authenticate     — valid JWT, attaches req.user
//     2. rateLimiter      — 60 req/min per user (Redis sliding window)
//     3. validateNearby   — parse & coerce ?lat &lng &radius_km &limit &madhab
//     4. getNearbyMosques — Redis GEO controller
//
//   POST /:mosqueId/timings/upload
//     1. authenticate          — valid JWT, attaches req.user
//     2. multer upload.single  — parses multipart/form-data, stores file in memory
//     3. processTimetableImage — Gemini OCR → Postgres write
//
//   GET  /:mosqueId/timings  — stub (Sprint 4 next)
//   POST /                   — stub (Sprint 4 next)
//
// IMPORTANT: authenticate is a NAMED export from authenticate.js.
//   `import authenticate` (default) would silently be undefined at runtime.
//   `import { authenticate }` (named) is correct and matches the export.
//
// IMPORTANT: The /nearby middleware chain (rateLimiter + validateNearby)
//   was intentionally kept. Removing it strips Redis rate limiting and
//   GPS coordinate validation from the production path — a security regression.
// =============================================================================

import { Router }                 from 'express';
import multer                     from 'multer';
import { authenticate }           from './authenticate.js';
import { rateLimiter }            from './rateLimiter.js';
import { validateNearby }         from './validateNearby.js';
import { getNearbyMosques }       from './mosques.nearby.controller.js';
import { processTimetableImage, listAllMosques, verifyTimings }  from './mosques.admin.controller.js';

const router = Router();

// ---------------------------------------------------------------------------
// Multer configuration — memory storage (no temp files on disk)
// ---------------------------------------------------------------------------
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize:  5 * 1024 * 1024, // 5 MB — large enough for a phone photo
    files:     1,                // only one file per request
  },
  fileFilter: (_req, file, cb) => {
    const allowed = ['image/jpeg', 'image/png', 'image/webp', 'image/heic'];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      // Reject immediately with a descriptive error (multer calls next(err))
      cb(new multer.MulterError('LIMIT_UNEXPECTED_FILE', `Unsupported type: ${file.mimetype}`));
    }
  },
});

// ---------------------------------------------------------------------------
// Multer error handler — converts multer errors to our standard envelope
// ---------------------------------------------------------------------------
function handleMulterError(err, _req, res, next) {
  if (err instanceof multer.MulterError) {
    const messages = {
      LIMIT_FILE_SIZE:        'Image exceeds the 5 MB size limit.',
      LIMIT_UNEXPECTED_FILE:  err.message || 'Unexpected file field.',
      LIMIT_FILE_COUNT:       'Only one file may be uploaded at a time.',
    };
    return res.status(413).json({
      error: {
        code:    'FILE_TOO_LARGE',
        message: messages[err.code] ?? `Upload error: ${err.message}`,
      },
    });
  }
  return next(err);
}

// ---------------------------------------------------------------------------
// GET /v1/mosques
// List all mosques (for selection dropdown in web admin panel)
// ---------------------------------------------------------------------------
router.get('/', authenticate, listAllMosques);

// ---------------------------------------------------------------------------
// GET /v1/mosques/nearby
// Full middleware chain preserved — rateLimiter and validateNearby are NOT optional
// ---------------------------------------------------------------------------
router.get(
  '/nearby',
  authenticate,
  rateLimiter('nearby', 60, 60_000),
  validateNearby,
  getNearbyMosques,
);

// ---------------------------------------------------------------------------
// POST /v1/mosques/:mosqueId/timings/upload
// OCR Pipeline: photo → Gemini Vision → Postgres (pending verification)
// TODO Sprint 5: add isAdmin middleware before upload.single()
// ---------------------------------------------------------------------------
router.post(
  '/:mosqueId/timings/upload',
  authenticate,
  upload.single('timetable'),
  handleMulterError,
  processTimetableImage,
);

// ---------------------------------------------------------------------------
// PUT /v1/mosques/:mosqueId/timings/:timingId/verify
// Verification Pipeline: admin corrects times + sets status to verified
// ---------------------------------------------------------------------------
router.put('/:mosqueId/timings/:timingId/verify', authenticate, verifyTimings);

// ---------------------------------------------------------------------------
// Placeholder stubs — to be implemented in subsequent sprints
// ---------------------------------------------------------------------------

// GET /v1/mosques/:mosqueId/timings  — fetch verified prayer timings
router.get('/:mosqueId/timings', authenticate, (_req, res) => {
  res.status(501).json({ error: { code: 'NOT_IMPLEMENTED', message: 'Coming soon.' } });
});

// POST /v1/mosques  — register a new mosque
router.post('/', authenticate, (_req, res) => {
  res.status(501).json({ error: { code: 'NOT_IMPLEMENTED', message: 'Coming soon.' } });
});

export default router;
