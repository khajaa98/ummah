# Local dev with ngrok — backend on your laptop, phone talks to it via HTTPS

This is the fastest, zero-cost path to having your Android phone talk to a
real backend with prayer timings + check-ins working. No AWS, no Fly, no
Docker. Just:

- **Neon.tech** (free) → managed Postgres
- **Upstash** (free) → managed Redis
- **Your laptop** → runs the Node backend
- **ngrok** (free) → exposes localhost:8080 as a public HTTPS URL

Total time: **20 minutes**. Cost: **$0/mo**. Caveat: backend goes down when
your laptop sleeps or you close the terminal.

---

## Step 1 · Neon Postgres (3 min)

1. Go to <https://neon.tech> → **Sign up** (Google/GitHub login is fastest)
2. After signup, you're dropped into a "Create your first project" page
3. **Project name:** `ummah`
4. **Postgres version:** 16
5. **Region:** pick the one closest to you (Mumbai/Singapore are options)
6. Click **Create project**

It auto-creates a database called `neondb` and shows you a connection
string that looks like:

```
postgresql://ummah_owner:abc123xyz@ep-cool-name-12345.ap-southeast-1.aws.neon.tech/neondb?sslmode=require
```

**Copy that entire string.** This is your `DATABASE_URL`.

> The free tier gives you 0.5 GB storage + 191.9 compute-hours/month —
> more than enough for testing.

## Step 2 · Upstash Redis (3 min)

1. Go to <https://upstash.com> → **Sign up**
2. Console → **Create Database**
3. **Name:** `ummah-cache`
4. **Type:** Regional (cheaper than Global)
5. **Region:** Same as Neon (Mumbai/Singapore)
6. **TLS:** Enable (default)
7. Click **Create**

On the database page, scroll to **Connect to your database** → toggle to
"Redis Connect". Note these three values:

| | Where to find it on Upstash dashboard |
|---|---|
| `REDIS_HOST` | Endpoint (e.g. `apt-bear-12345.upstash.io`) |
| `REDIS_PORT` | Port (usually `6379`) |
| `REDIS_PASSWORD` | Password (click "Show" to reveal) |

> Free tier: 10,000 commands/day. We use ~5 commands per nearby-mosque
> query, so that's 2,000 requests/day before you hit the limit.

## Step 3 · Wire up the backend (5 min)

From `Ummah-backend/`:

```powershell
cd C:\Users\skhaj\Downloads\Ummah\ummah\Ummah-backend

# Generate a JWT secret
$jwt = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(
    [guid]::NewGuid().ToString() + [guid]::NewGuid().ToString()))

# Write .env — replace the placeholders with values from Step 1 + 2
@"
DATABASE_URL=PASTE_NEON_URL_HERE
REDIS_HOST=PASTE_UPSTASH_ENDPOINT_HERE
REDIS_PORT=6379
REDIS_PASSWORD=PASTE_UPSTASH_PASSWORD_HERE
JWT_SECRET=$jwt
NODE_ENV=development
PORT=8080
"@ | Out-File -FilePath .env -Encoding ascii

notepad .env   # fill in the three PASTE_... placeholders, save, close
```

> Upstash requires TLS. Open `redis.js` and confirm or add `tls: {}` to the
> Redis client config — see "Upstash TLS" section at the bottom if your
> ioredis is rejecting the connection.

Now install + migrate + seed:

```powershell
npm install
npx prisma generate --schema=./schema.prisma

# Load .env and apply migrations against Neon
$envContent = Get-Content .env | Where-Object { $_ -match '^\w+=' }
foreach ($line in $envContent) {
    $key, $val = $line -split '=', 2
    [Environment]::SetEnvironmentVariable($key, $val, 'Process')
}
npx prisma migrate deploy --schema=./schema.prisma

# Optional: seed demo mosques
node seed.js
```

If `seed.js` doesn't exist or errors, skip it — you can insert mosques
later via psql or the Neon SQL editor (web UI).

## Step 4 · Run the backend (1 min)

```powershell
# Still in Ummah-backend/, with env vars already loaded:
node server.js
```

Expected output:

```
[Redis] connected
[Ummah] Server listening on port 8080 (development)
```

Open <http://localhost:8080/health> in your browser — should show
`{"status":"ok"}`. Leave this terminal window open.

## Step 5 · ngrok tunnel (5 min)

In a **second** PowerShell window (don't close the first):

```powershell
# Install ngrok via winget
winget install --id=Ngrok.Ngrok -e --accept-source-agreements --accept-package-agreements
# Close + reopen PowerShell so ngrok is on PATH
```

ngrok needs an authtoken (one-time):

1. Go to <https://dashboard.ngrok.com/signup> → sign up free
2. After login → **Your Authtoken** → copy
3. Paste into PowerShell:

```powershell
ngrok config add-authtoken <YOUR_TOKEN>
```

Now start the tunnel:

```powershell
ngrok http 8080
```

You'll see a UI like:

```
ngrok                                                          (Ctrl+C to quit)

Session Status                online
Account                       you@email.com (Plan: Free)
Region                        India (in)
Latency                       12ms
Web Interface                 http://127.0.0.1:4040
Forwarding                    https://abcd-1234-5678.ngrok-free.app -> http://localhost:8080
```

**Copy the `https://abcd-1234-5678.ngrok-free.app` URL.** That's your
backend's public address. Leave this terminal open too.

## Step 6 · Rebuild the APK with the ngrok URL (3 min)

In a **third** PowerShell window:

```powershell
cd C:\Users\skhaj\Downloads\Ummah\ummah
$env:PATH = "C:\Users\skhaj\dev\flutter\bin;$env:PATH"
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"

flutter build apk --release `
    --dart-define=API_BASE_URL=https://abcd-1234-5678.ngrok-free.app
```

(Replace with your actual ngrok URL.) Wait ~3 min for the build.

## Step 7 · Install on your phone

Per `SIDELOAD.md`:

```powershell
C:\Users\skhaj\AppData\Local\Android\Sdk\platform-tools\adb.exe install -r `
  "C:\Users\skhaj\Downloads\Ummah\ummah\build\app\outputs\flutter-apk\app-release.apk"
```

Or copy `app-release.apk` to your phone via email/Drive and tap to install.

## Step 8 · Smoke test

1. Open Ummah on your phone, tap through onboarding, accept location.
2. The Mosques tab should query your laptop's backend via ngrok.
3. If the database is empty, you'll see the "no mosques found" empty state
   (that's correct behavior — not an error).
4. Add a test mosque from your laptop:

   ```powershell
   # In a fresh PowerShell window, with .env loaded:
   $envContent = Get-Content .env | Where-Object { $_ -match '^\w+=' }
   foreach ($line in $envContent) {
       $key, $val = $line -split '=', 2
       [Environment]::SetEnvironmentVariable($key, $val, 'Process')
   }

   # Connect via psql (install via winget if needed: winget install PostgreSQL.psql)
   psql $env:DATABASE_URL
   ```

   Then in the psql prompt:

   ```sql
   INSERT INTO "Mosque" (id, name, "nameAr", latitude, longitude,
       madhab, status, "createdAt", "updatedAt", city, country, "countryCode")
   VALUES (gen_random_uuid(), 'Test Mosque', 'مسجد', 17.4, 78.5,
       'hanafi', 'verified', now(), now(), 'Hyderabad', 'India', 'IN');
   ```

5. Pull-to-refresh on your phone — the test mosque should appear.

---

## Troubleshooting

### ngrok URL changes every restart

Free tier ngrok issues a new random subdomain every time you `ngrok http 8080`.
If you have to restart, you'll need to rebuild the APK with the new URL.
**Workaround:** the paid ngrok plan ($10/mo) gives you a stable subdomain.

### Phone can't reach the URL

Your network security config (Flutter app) only allows cleartext for LAN
ranges + localhost. ngrok URLs are HTTPS, so this should work. If you get
"Connection error" on the mosque list anyway, check:

```powershell
curl https://your-ngrok-url.ngrok-free.app/health
```

If that fails from your laptop, the issue is upstream (backend not running
or ngrok crashed). If it succeeds from your laptop but fails from the phone,
check the APK's dart-define — rebuild if needed.

### Upstash TLS handshake errors

ioredis needs `tls: {}` in its config when connecting to Upstash. If you see
`ECONNRESET` in the backend logs, edit `redis.js` line ~10:

```javascript
const redis = new Redis({
  host:     process.env.REDIS_HOST,
  port:     parseInt(process.env.REDIS_PORT || '6379', 10),
  password: process.env.REDIS_PASSWORD,
  tls:      process.env.REDIS_HOST?.includes('upstash') ? {} : undefined,
  // ...rest unchanged
});
```

### Prisma migrate fails with "permission denied"

Neon's default user has full permission to the `public` schema. If you see
permission errors, check that your `DATABASE_URL` connects to `neondb` (not
`postgres`) and uses the `_owner` user, not a read-only one.

### Backend crashes every few minutes

That's the Neon "scale-to-zero" — the free-tier compute auto-pauses after
5 min of idle. First request after pause takes ~1 sec to wake. Not a real
problem, just slower first requests.

### My laptop went to sleep — phone now sees errors

ngrok dies when your laptop sleeps. Re-open both terminals (`node server.js`
and `ngrok http 8080`) and the new URL goes in a fresh APK build. Or set
your laptop to never sleep while plugged in.

---

## When you're ready for real deployment

This setup is great for getting the app on your phone *today* and demoing
to friends. For sustained use:

- **Free / cheap upgrade path:** Fly.io (`fly.toml` is already in this
  directory). Run `fly apps create ummah-skhaj --org personal` then
  `fly deploy`. ~5 min. $0–5/mo.
- **AWS path:** see `AWS_DEPLOY.md` once you have an AWS account without
  the SCP restriction (i.e. a fresh personal account, not your current
  org-joined one).
