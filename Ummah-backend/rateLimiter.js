// src/middleware/rateLimiter.js
// =============================================================================
// Redis-backed sliding-window rate limiter.
// Contract spec: max 60 proximity queries per user per minute.
//
// Uses a Redis sorted set (ZSET) per user:
//   key:   ratelimit:nearby:{userId}
//   score: Unix timestamp (ms)
//   value: request UUID (ensures uniqueness within the same ms)
//
// On each request:
//   1. Remove all members with score < (now - windowMs)
//   2. Count remaining members
//   3. If count >= limit → reject 429
//   4. Add current request
//   5. Set TTL = windowMs so idle keys expire automatically
// =============================================================================

import { randomUUID } from 'crypto';
import redis from './redis.js';

const WINDOW_MS    = 60_000;  // 1 minute
const WINDOW_LIMIT = 60;      // requests per window per user

/**
 * Factory — returns rate-limiter middleware for a named action.
 * Keeping it generic allows reuse across routes.
 *
 * @param {string} action  - e.g. 'nearby'
 * @param {number} [limit] - override default limit
 * @param {number} [windowMs] - override default window
 */
export function rateLimiter(action, limit = WINDOW_LIMIT, windowMs = WINDOW_MS) {
  return async function rateLimit(req, res, next) {
    if (!req.user?.id) return next(); // unauthenticated; let authenticate() handle it

    const key = `ratelimit:${action}:${req.user.id}`;
    const now = Date.now();
    const windowStart = now - windowMs;
    const requestId   = randomUUID();

    try {
      const pipeline = redis.pipeline();
      pipeline.zremrangebyscore(key, '-inf', windowStart);
      pipeline.zcard(key);
      pipeline.zadd(key, now, requestId);
      pipeline.pexpire(key, windowMs);

      const results = await pipeline.exec();
      const currentCount = results[1][1]; // zcard result before this request is added

      if (currentCount >= limit) {
        res.setHeader('Retry-After', Math.ceil(windowMs / 1000));
        return res.status(429).json({
          error: {
            code:    'RATE_LIMITED',
            message: `Too many requests. Maximum ${limit} per ${windowMs / 1000}s window.`,
            retryAfterSeconds: Math.ceil(windowMs / 1000),
          },
        });
      }

      // Expose rate limit state in response headers (standard practice)
      res.setHeader('X-RateLimit-Limit',     limit);
      res.setHeader('X-RateLimit-Remaining', Math.max(0, limit - currentCount - 1));
      res.setHeader('X-RateLimit-Reset',     Math.ceil((now + windowMs) / 1000));

      return next();
    } catch (err) {
      // If Redis is unavailable, fail open — don't block the user — but log
      console.error('[RateLimiter] Redis error, failing open:', err);
      return next();
    }
  };
}
