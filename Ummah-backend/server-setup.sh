#!/usr/bin/env bash
# server-setup.sh
# =============================================================================
# One-shot bootstrap for the Ummah backend on a fresh Ubuntu 22.04 EC2 instance.
#
# What this does:
#   1. Updates apt + installs Node.js 20, Nginx, certbot, build deps
#   2. Creates a non-root 'ummah' user to run the app
#   3. Clones (or expects pre-uploaded) the Ummah-backend source under /srv/ummah
#   4. Writes .env from the values you pasted at the prompts
#   5. Runs `npm ci` + `npx prisma migrate deploy` + `node seed.js`
#   6. Installs PM2 + registers the app as a systemd service
#   7. Configures Nginx as an HTTPS reverse proxy on your DuckDNS subdomain
#   8. Issues a Let's Encrypt certificate
#
# Run:
#   curl -fsSL <gist-or-paste-this-file-url> | sudo bash
#
# OR (recommended):
#   scp this file to the instance, then:
#     sudo bash server-setup.sh
#
# Idempotent: re-running re-applies state; safe.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root (sudo bash server-setup.sh)"
  exit 1
fi

if ! grep -q "Ubuntu 22.04" /etc/lsb-release 2>/dev/null && ! grep -q "Ubuntu 24" /etc/lsb-release 2>/dev/null; then
  echo "WARNING: this script was written for Ubuntu 22.04/24.04 — proceed at own risk"
fi

# ---------------------------------------------------------------------------
# 1. Prompt for runtime config (interactive)
# ---------------------------------------------------------------------------

read -p "DuckDNS subdomain (e.g. 'ummah-skhaj' for ummah-skhaj.duckdns.org): " DUCK_SUBDOMAIN
read -p "DuckDNS token (get from https://www.duckdns.org after login): " DUCK_TOKEN
read -p "Email for Let's Encrypt (renewal notifications go here): " ACME_EMAIL
read -p "DATABASE_URL (full postgres URL from .ummah-deploy.env): " DATABASE_URL
read -p "REDIS_HOST: " REDIS_HOST
read -p "REDIS_PORT [6379]: " REDIS_PORT
REDIS_PORT=${REDIS_PORT:-6379}
read -p "REDIS_PASSWORD (leave blank for ElastiCache without auth): " REDIS_PASSWORD
read -p "JWT_SECRET (from .ummah-deploy.env, long random string): " JWT_SECRET

DOMAIN="${DUCK_SUBDOMAIN}.duckdns.org"

# ---------------------------------------------------------------------------
# 2. System packages
# ---------------------------------------------------------------------------

echo "==> Updating apt..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

echo "==> Installing system packages..."
apt-get install -y -qq \
    curl ca-certificates gnupg lsb-release \
    build-essential git \
    nginx certbot python3-certbot-nginx \
    postgresql-client \
    ufw

# Node.js 20 LTS via NodeSource
if ! command -v node >/dev/null || [[ "$(node -v)" != v20* ]]; then
  echo "==> Installing Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y -qq nodejs
fi
echo "    node: $(node -v)"
echo "    npm:  $(npm -v)"

# PM2 — process manager
npm install --silent -g pm2

# ---------------------------------------------------------------------------
# 3. Create dedicated user + directory
# ---------------------------------------------------------------------------

if ! id -u ummah >/dev/null 2>&1; then
  echo "==> Creating 'ummah' user..."
  useradd -r -m -d /srv/ummah -s /bin/bash ummah
fi

install -d -o ummah -g ummah /srv/ummah/app
install -d -o ummah -g ummah /srv/ummah/logs

# ---------------------------------------------------------------------------
# 4. Check that the backend source is uploaded
# ---------------------------------------------------------------------------

if [[ ! -f /srv/ummah/app/package.json ]]; then
  echo ""
  echo "============================================================"
  echo " ERROR: Backend source not found at /srv/ummah/app/"
  echo ""
  echo " From your local machine, run:"
  echo "   cd C:\\Users\\skhaj\\Downloads\\Ummah\\ummah\\Ummah-backend"
  echo "   scp -i ..\\ummah-key.pem -r * ubuntu@\$(this-instance):/tmp/ummah/"
  echo "   ssh -i ..\\ummah-key.pem ubuntu@\$(this-instance)"
  echo "   sudo mv /tmp/ummah/* /srv/ummah/app/"
  echo "   sudo chown -R ummah:ummah /srv/ummah/app/"
  echo "   sudo bash /srv/ummah/app/server-setup.sh"
  echo "============================================================"
  exit 1
fi

chown -R ummah:ummah /srv/ummah/app

# ---------------------------------------------------------------------------
# 5. Write .env (read by the Node process)
# ---------------------------------------------------------------------------

echo "==> Writing /srv/ummah/app/.env..."
cat > /srv/ummah/app/.env <<EOF
DATABASE_URL=${DATABASE_URL}
REDIS_HOST=${REDIS_HOST}
REDIS_PORT=${REDIS_PORT}
REDIS_PASSWORD=${REDIS_PASSWORD}
JWT_SECRET=${JWT_SECRET}
NODE_ENV=production
PORT=8080
EOF
chmod 600 /srv/ummah/app/.env
chown ummah:ummah /srv/ummah/app/.env

# ---------------------------------------------------------------------------
# 6. npm install + migrations + seed
# ---------------------------------------------------------------------------

echo "==> Installing npm dependencies (this takes a minute)..."
sudo -u ummah bash -c "cd /srv/ummah/app && npm ci --omit=dev"

echo "==> Generating Prisma client..."
sudo -u ummah bash -c "cd /srv/ummah/app && npx prisma generate --schema=./schema.prisma"

echo "==> Running migrations against RDS..."
sudo -u ummah bash -c "cd /srv/ummah/app && set -a && source .env && set +a && npx prisma migrate deploy --schema=./schema.prisma"

if [[ -f /srv/ummah/app/seed.js ]]; then
  echo "==> Seeding database with demo mosques..."
  sudo -u ummah bash -c "cd /srv/ummah/app && set -a && source .env && set +a && node seed.js" || \
    echo "    seed.js exited non-zero — continuing anyway"
fi

# ---------------------------------------------------------------------------
# 7. PM2 as a systemd service
# ---------------------------------------------------------------------------

echo "==> Starting Ummah under PM2..."
sudo -u ummah bash -c "cd /srv/ummah/app && pm2 delete ummah 2>/dev/null || true"
sudo -u ummah bash -c "cd /srv/ummah/app && pm2 start server.js --name ummah --time"
sudo -u ummah bash -c "pm2 save"

# Generate + install the systemd unit so the app survives reboots
env PATH=$PATH:/usr/bin pm2 startup systemd -u ummah --hp /srv/ummah | tail -n 1 | bash
sudo -u ummah bash -c "pm2 save"

echo "==> Verifying app responds on :8080..."
sleep 3
if curl -fsS http://127.0.0.1:8080/health | grep -q '"ok"'; then
  echo "    /health → OK"
else
  echo "    WARNING: /health did not return OK. Check 'sudo -u ummah pm2 logs ummah'"
fi

# ---------------------------------------------------------------------------
# 8. DuckDNS — point the subdomain at this EC2 instance
# ---------------------------------------------------------------------------

echo "==> Registering this instance's IP with DuckDNS..."
PUBLIC_IP=$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')
curl -fsS "https://www.duckdns.org/update?domains=${DUCK_SUBDOMAIN}&token=${DUCK_TOKEN}&ip=${PUBLIC_IP}" \
  | tee /dev/stderr | grep -q OK || { echo "DuckDNS update failed"; exit 1; }
echo "    ${DOMAIN} → ${PUBLIC_IP}"

# Keep DNS fresh — write a 5-min crontab entry
cat > /etc/cron.d/duckdns <<EOF
*/5 * * * * root /usr/bin/curl -fsS "https://www.duckdns.org/update?domains=${DUCK_SUBDOMAIN}&token=${DUCK_TOKEN}&ip=" > /var/log/duckdns.log 2>&1
EOF
chmod 644 /etc/cron.d/duckdns

# ---------------------------------------------------------------------------
# 9. Nginx reverse proxy
# ---------------------------------------------------------------------------

echo "==> Configuring Nginx..."
cat > /etc/nginx/sites-available/ummah <<EOF
# Pre-Let's-Encrypt: plain HTTP only.
# Certbot will rewrite this file to add the HTTPS server block + redirect.
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    client_max_body_size 5M;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 30s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/ummah /etc/nginx/sites-enabled/ummah
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

# ---------------------------------------------------------------------------
# 10. Let's Encrypt
# ---------------------------------------------------------------------------

echo "==> Issuing Let's Encrypt certificate for ${DOMAIN}..."
certbot --nginx \
    --non-interactive \
    --agree-tos \
    --email "${ACME_EMAIL}" \
    --domains "${DOMAIN}" \
    --redirect

systemctl enable certbot.timer
systemctl start  certbot.timer

# ---------------------------------------------------------------------------
# 11. Done
# ---------------------------------------------------------------------------

echo ""
echo "============================================================"
echo " Ummah backend is LIVE."
echo "============================================================"
echo ""
echo " Public URL:   https://${DOMAIN}"
echo " Health:       https://${DOMAIN}/health"
echo ""
echo " Rebuild your APK with:"
echo "   flutter build apk --release --dart-define=API_BASE_URL=https://${DOMAIN}"
echo ""
echo " Inspect logs anytime:"
echo "   sudo -u ummah pm2 logs ummah --lines 100"
echo ""
echo " Restart app:"
echo "   sudo -u ummah pm2 restart ummah"
echo ""
