// src/app.js
// =============================================================================
// Express application setup.
// =============================================================================

import express        from 'express';
import helmet         from 'helmet';
import morgan         from 'morgan';
import mosquesRouter  from './mosques.router.js';

const app = express();

// ---------------------------------------------------------------------------
// Security headers
// ---------------------------------------------------------------------------
app.use(helmet());

// ---------------------------------------------------------------------------
// CORS Support (Allows Flutter Web to access API endpoints)
// ---------------------------------------------------------------------------
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

// ---------------------------------------------------------------------------
// Body parsing
// ---------------------------------------------------------------------------
app.use(express.json({ limit: '256kb' }));

// ---------------------------------------------------------------------------
// Request logging
// IMPORTANT — privacy requirement:
//   The 'tiny' format logs only method, path (no query string), status, and
//   response time. This ensures ?lat=&lng= params are never written to logs.
//   Do NOT change to 'combined' or 'dev' without adding a query-strip transform.
// ---------------------------------------------------------------------------
app.use(
  morgan('tiny', {
    // Additionally skip health-check noise
    skip: (req) => req.path === '/health',
  }),
);

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------
app.use('/v1/mosques', mosquesRouter);

// Health check (no auth, used by load balancer)
app.get('/health', (_req, res) => res.json({ status: 'ok' }));

// ---------------------------------------------------------------------------
// 404 catch-all
// ---------------------------------------------------------------------------
app.use((_req, res) => {
  res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Route not found.' } });
});

// ---------------------------------------------------------------------------
// Global error handler
// ---------------------------------------------------------------------------
app.use((err, _req, res, _next) => {
  console.error('[Unhandled error]', err);
  res.status(500).json({
    error: { code: 'INTERNAL_ERROR', message: 'An unexpected error occurred.' },
  });
});

export default app;
