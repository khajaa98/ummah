# =============================================================================
# Ummah backend — production Dockerfile (multi-stage).
#
# Stage 1 ("deps") installs production-only Node modules with a deterministic
# npm ci. Stage 2 ("runner") copies just the artifacts we need, runs as a
# non-root user, and tags the listening port for Fly.io's proxy.
# =============================================================================

# ---------- Stage 1: deps + Prisma generate ----------
FROM node:20-alpine AS deps

WORKDIR /app

# Prisma engine needs OpenSSL
RUN apk add --no-cache openssl libc6-compat

# Deterministic install — fails if package-lock.json drifts
COPY package*.json ./
RUN npm ci --omit=dev

# Copy schema + generate Prisma client into the same node_modules tree
COPY schema.prisma ./schema.prisma
RUN npx prisma generate --schema=./schema.prisma

# ---------- Stage 2: runtime ----------
FROM node:20-alpine AS runner

WORKDIR /app

RUN apk add --no-cache openssl libc6-compat tini && \
    addgroup -g 1001 -S nodejs && \
    adduser  -u 1001 -S ummah -G nodejs

# Bring in deps + generated client from stage 1
COPY --from=deps --chown=ummah:nodejs /app/node_modules ./node_modules
COPY --from=deps --chown=ummah:nodejs /app/package*.json ./

# Application source
COPY --chown=ummah:nodejs . .

USER ummah

ENV NODE_ENV=production \
    PORT=8080

EXPOSE 8080

# tini reaps zombie processes (Fly's machine SIGTERMs need to propagate cleanly)
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "server.js"]
