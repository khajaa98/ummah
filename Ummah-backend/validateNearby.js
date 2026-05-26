// src/middleware/validateNearby.js
// =============================================================================
// Express middleware — validates and coerces query params for GET /mosques/nearby.
// Attaches a clean `req.nearbyParams` object so the controller never touches
// raw query strings.
//
// Validation rules match the API contract exactly:
//   lat       required, float, -90 ≤ lat ≤ 90
//   lng       required, float, -180 ≤ lng ≤ 180
//   radius_km optional, float, 0 < r ≤ 50, default 5.0
//   limit     optional, integer, 1 ≤ n ≤ 100, default 20
//   madhab    optional, one of the Madhab enum values
// =============================================================================

const VALID_MADHABS = new Set(['Hanafi', 'Shafii', 'Maliki', 'Hanbali']);

const DEFAULT_RADIUS = 5.0;
const MAX_RADIUS     = 50.0;
const DEFAULT_LIMIT  = 20;
const MAX_LIMIT      = 100;

/**
 * @param {import('express').Request}  req
 * @param {import('express').Response} res
 * @param {import('express').NextFunction} next
 */
export function validateNearby(req, res, next) {
  const errors = [];

  // --- lat ---
  const lat = parseFloat(req.query.lat);
  if (req.query.lat === undefined || req.query.lat === '') {
    errors.push({ field: 'lat', message: 'lat is required' });
  } else if (isNaN(lat) || lat < -90 || lat > 90) {
    errors.push({ field: 'lat', message: 'lat must be a number between -90 and 90' });
  }

  // --- lng ---
  const lng = parseFloat(req.query.lng);
  if (req.query.lng === undefined || req.query.lng === '') {
    errors.push({ field: 'lng', message: 'lng is required' });
  } else if (isNaN(lng) || lng < -180 || lng > 180) {
    errors.push({ field: 'lng', message: 'lng must be a number between -180 and 180' });
  }

  // --- radius_km ---
  let radiusKm = DEFAULT_RADIUS;
  if (req.query.radius_km !== undefined) {
    radiusKm = parseFloat(req.query.radius_km);
    if (isNaN(radiusKm) || radiusKm <= 0) {
      errors.push({ field: 'radius_km', message: 'radius_km must be a positive number' });
    } else if (radiusKm > MAX_RADIUS) {
      errors.push({ field: 'radius_km', message: `radius_km must not exceed ${MAX_RADIUS} km` });
    }
  }

  // --- limit ---
  let limit = DEFAULT_LIMIT;
  if (req.query.limit !== undefined) {
    limit = parseInt(req.query.limit, 10);
    if (isNaN(limit) || limit < 1) {
      errors.push({ field: 'limit', message: 'limit must be a positive integer' });
    } else if (limit > MAX_LIMIT) {
      errors.push({ field: 'limit', message: `limit must not exceed ${MAX_LIMIT}` });
    }
  }

  // --- madhab (optional filter) ---
  let madhab = null;
  if (req.query.madhab !== undefined) {
    if (!VALID_MADHABS.has(req.query.madhab)) {
      errors.push({
        field:   'madhab',
        message: `madhab must be one of: ${[...VALID_MADHABS].join(', ')}`,
      });
    } else {
      madhab = req.query.madhab;
    }
  }

  if (errors.length > 0) {
    return res.status(400).json({
      error: {
        code:    'INVALID_COORDINATES',
        message: 'One or more query parameters are invalid.',
        details: errors,
      },
    });
  }

  // Attach coerced params — controller reads only from here
  req.nearbyParams = { lat, lng, radiusKm, limit, madhab };
  return next();
}
