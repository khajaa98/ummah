// Ummah-backend/auth.controller.js
// =============================================================================
// Authentication controller — POST /v1/auth/register and POST /v1/auth/login
//
// Adds the missing user-facing auth endpoints to the Ummah backend.
// Your existing `authenticate.js` (JWT verification middleware) is unchanged.
// This file PROVIDES tokens; authenticate.js VERIFIES them.
//
// Security:
//   • Passwords hashed with bcrypt (cost factor 12)
//   • Email stored as SHA-256 hash for DPDPA data-minimization
//   • JWT signed with HS256, 30-day expiry (matches your generateToken.js)
//   • Constant-time-ish login failure path (dummy bcrypt compare for missing
//     users) to mitigate user-enumeration timing attacks
//
// Pre-requisites:
//   • bcrypt: `npm install bcrypt` from inside Ummah-backend/
//   • JWT_SECRET env var must be set (you already have this)
//   • Prisma User model must have: id, displayName, emailHash, passwordHash,
//     role, locale, deletedAt fields (check schema.prisma)
// =============================================================================

import crypto from 'crypto';
import jwt    from 'jsonwebtoken';
import prisma from './prisma.js';

// Dynamic bcrypt import — works whether the installed package is `bcrypt`
// (native) or `bcryptjs` (pure JS fallback if native compile fails)
let bcrypt;
try { bcrypt = (await import('bcrypt')).default; }
catch (_) { bcrypt = (await import('bcryptjs')).default; }

const JWT_SECRET    = process.env.JWT_SECRET;
const JWT_EXPIRY    = '30d';
const BCRYPT_ROUNDS = 12;

if (!JWT_SECRET) {
  throw new Error('JWT_SECRET environment variable is not set.');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function hashEmail(email) {
  return crypto
    .createHash('sha256')
    .update(email.trim().toLowerCase())
    .digest('hex');
}

function signToken(user) {
  return jwt.sign(
    { sub: user.id, role: user.role, locale: user.locale },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRY },
  );
}

function validateEmail(email) {
  if (typeof email !== 'string') return 'email must be a string';
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) return 'invalid email';
  return null;
}

function validatePassword(password) {
  if (typeof password !== 'string') return 'password must be a string';
  if (password.length < 8) return 'password must be ≥ 8 characters';
  return null;
}

// ---------------------------------------------------------------------------
// POST /v1/auth/register
// ---------------------------------------------------------------------------

export async function register(req, res) {
  const { email, password, display_name } = req.body ?? {};

  const errors = [];
  const ee = validateEmail(email);
  if (ee) errors.push({ field: 'email', message: ee });

  const pe = validatePassword(password);
  if (pe) errors.push({ field: 'password', message: pe });

  if (!display_name || typeof display_name !== 'string' || display_name.trim().length < 2) {
    errors.push({ field: 'display_name', message: 'display_name required (≥ 2 chars)' });
  }

  if (errors.length > 0) {
    return res.status(400).json({
      error: { code: 'INVALID_PAYLOAD', message: 'Invalid registration data.', details: errors },
    });
  }

  const emailHash = hashEmail(email);

  const existing = await prisma.user.findUnique({ where: { emailHash } });
  if (existing) {
    return res.status(409).json({
      error: { code: 'EMAIL_TAKEN', message: 'An account with this email already exists.' },
    });
  }

  const passwordHash = await bcrypt.hash(password, BCRYPT_ROUNDS);

  let user;
  try {
    user = await prisma.user.create({
      data: {
        displayName:  display_name.trim(),
        emailHash,
        passwordHash,
        role:         'member',
        locale:       'en',
      },
    });
  } catch (err) {
    console.error('[register] DB write failed:', err);
    return res.status(500).json({
      error: { code: 'DB_WRITE_FAILED', message: 'Could not create account. Please retry.' },
    });
  }

  const token = signToken(user);

  return res.status(201).json({
    token,
    user: {
      id:           user.id,
      display_name: user.displayName,
      role:         user.role,
      locale:       user.locale,
    },
  });
}

// ---------------------------------------------------------------------------
// POST /v1/auth/login
// ---------------------------------------------------------------------------

export async function login(req, res) {
  const { email, password } = req.body ?? {};

  const errors = [];
  const ee = validateEmail(email);
  if (ee) errors.push({ field: 'email', message: ee });

  const pe = validatePassword(password);
  if (pe) errors.push({ field: 'password', message: pe });

  if (errors.length > 0) {
    return res.status(400).json({
      error: { code: 'INVALID_PAYLOAD', message: 'Invalid login data.', details: errors },
    });
  }

  const emailHash = hashEmail(email);
  const user      = await prisma.user.findUnique({ where: { emailHash } });

  // Always run bcrypt.compare even if user missing — prevents timing attacks
  // that could reveal which emails are registered.
  const dummyHash = '$2b$12$invalidsaltinvalidsaltinvalidsaltinvalidsaltinvalidsa';
  const ok = await bcrypt.compare(password, user?.passwordHash ?? dummyHash);

  if (!user || user.deletedAt !== null || !ok) {
    return res.status(401).json({
      error: { code: 'INVALID_CREDENTIALS', message: 'Email or password is incorrect.' },
    });
  }

  const token = signToken(user);

  return res.status(200).json({
    token,
    user: {
      id:           user.id,
      display_name: user.displayName,
      role:         user.role,
      locale:       user.locale,
    },
  });
}
