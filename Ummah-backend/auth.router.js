// Ummah-backend/auth.router.js
// =============================================================================
// Mounts /v1/auth/register and /v1/auth/login.
//
// No `authenticate` middleware here — these endpoints issue tokens, so they
// can't require a token. They're protected instead by the rateLimiter to
// prevent brute-force credential attacks.
//
// In app.js, mount with:
//   import authRouter from './auth.router.js';
//   app.use('/v1/auth', authRouter);
// =============================================================================

import { Router }          from 'express';
import { rateLimiter }     from './rateLimiter.js';
import { register, login } from './auth.controller.js';

const router = Router();

// 10 attempts per IP per minute. rateLimiter handles unauthenticated requests
// by falling back to IP-based limiting.
const authLimiter = rateLimiter('auth', 10, 60_000);

router.post('/register', authLimiter, register);
router.post('/login',    authLimiter, login);

export default router;
