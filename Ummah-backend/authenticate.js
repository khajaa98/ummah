// src/middleware/authenticate.js
// =============================================================================
// JWT Bearer token authentication middleware.
// Attaches `req.user = { id, role, locale }` on success.
// Soft-deleted users are rejected at this layer.
// =============================================================================

import jwt from 'jsonwebtoken';
import prisma from './prisma.js';

const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET) {
  throw new Error('JWT_SECRET environment variable is not set.');
}

/**
 * @param {import('express').Request}      req
 * @param {import('express').Response}     res
 * @param {import('express').NextFunction} next
 */
export async function authenticate(req, res, next) {
  const authHeader = req.headers['authorization'];
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      error: { code: 'UNAUTHORIZED', message: 'Missing or malformed Authorization header.' },
    });
  }

  const token = authHeader.slice(7);

  let payload;
  try {
    payload = jwt.verify(token, JWT_SECRET);
  } catch (err) {
    const isExpired = err.name === 'TokenExpiredError';
    return res.status(401).json({
      error: {
        code:    'UNAUTHORIZED',
        message: isExpired ? 'Token has expired.' : 'Invalid token.',
      },
    });
  }

  // Verify user still exists and is not soft-deleted
  const user = await prisma.user.findUnique({
    where:  { id: payload.sub },
    select: { id: true, role: true, locale: true, deletedAt: true },
  });

  if (!user || user.deletedAt !== null) {
    return res.status(401).json({
      error: { code: 'UNAUTHORIZED', message: 'User account not found or has been deactivated.' },
    });
  }

  req.user = { id: user.id, role: user.role, locale: user.locale };
  return next();
}
