// src/server.js
import app    from './app.js';
import prisma from './prisma.js';
import redis  from './redis.js';

const PORT = parseInt(process.env.PORT || '3000', 10);

const server = app.listen(PORT, () => {
  console.info(`[Ummah] Server listening on port ${PORT} (${process.env.NODE_ENV || 'development'})`);
});

// Graceful shutdown — close DB and Redis before process exits
async function shutdown(signal) {
  console.info(`[Ummah] ${signal} received — shutting down gracefully`);
  server.close(async () => {
    await prisma.$disconnect();
    redis.disconnect();
    process.exit(0);
  });
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));
