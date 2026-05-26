// src/utils/geohash.js
// =============================================================================
// Minimal geohash encoder — produces a base-32 prefix for GeoQueryLog.
// Precision 4  ≈ ±20 km   (≈40 × 20 km cell) — appropriate for aggregate analytics.
// Precision 5  ≈ ±2.4 km
// Precision 6  ≈ ±0.6 km  — use only if finer analytics are needed.
//
// We intentionally keep this internal rather than pulling a library to
// maintain zero additional runtime dependencies for this utility.
// =============================================================================

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/**
 * Encode a lat/lng pair to a geohash string of the given precision.
 *
 * @param {number} latitude   - WGS-84 latitude
 * @param {number} longitude  - WGS-84 longitude
 * @param {number} precision  - Number of base-32 characters (default: 4)
 * @returns {string}          - Geohash prefix
 */
export function encodeGeohash(latitude, longitude, precision = 4) {
  let idx  = 0;   // index into BASE32
  let bit  = 0;   // current bit position (0–4)
  let evenBit = true;
  let hash = '';

  let latMin = -90,  latMax = 90;
  let lngMin = -180, lngMax = 180;

  while (hash.length < precision) {
    if (evenBit) {
      // bisect longitude range
      const lngMid = (lngMin + lngMax) / 2;
      if (longitude >= lngMid) {
        idx = (idx << 1) | 1;
        lngMin = lngMid;
      } else {
        idx = idx << 1;
        lngMax = lngMid;
      }
    } else {
      // bisect latitude range
      const latMid = (latMin + latMax) / 2;
      if (latitude >= latMid) {
        idx = (idx << 1) | 1;
        latMin = latMid;
      } else {
        idx = idx << 1;
        latMax = latMid;
      }
    }
    evenBit = !evenBit;

    if (++bit === 5) {
      hash += BASE32[idx];
      bit  = 0;
      idx  = 0;
    }
  }

  return hash;
}
