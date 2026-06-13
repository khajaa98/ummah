# Deploying the Ummah backend to Fly.io

Beginner-friendly walkthrough. Estimated time: **20 minutes**. Cost: **$0/mo**
for the first ~2 months, then ~$5/mo once Postgres free credits run out.

## What you'll end up with

- A public HTTPS URL like `https://ummah-backend.fly.dev`
- A managed Postgres database (Fly's own Postgres-on-Machines)
- A managed Redis (Upstash, via Fly's wrapper)
- Auto-deploy on `git push` (optional — set up later)

---

## 1. Install the Fly CLI

On Windows (PowerShell, as Administrator):

```powershell
iwr https://fly.io/install.ps1 -useb | iex
```

Then **close and re-open PowerShell** so the new PATH takes effect. Verify:

```powershell
fly version
```

## 2. Sign up & log in

```powershell
fly auth signup       # if you don't have an account
# OR
fly auth login        # opens browser
```

Fly will ask for a credit card. They don't charge you unless you exceed the
free quota, which a hobby app won't.

## 3. Launch the app (this creates the Fly app & deploys)

From the `Ummah-backend/` directory:

```powershell
cd C:\Users\skhaj\Downloads\Ummah\ummah\Ummah-backend
fly launch --no-deploy --copy-config
```

Answers when prompted:

| Question                                | Answer                  |
| --------------------------------------- | ----------------------- |
| App name?                               | `ummah-backend` (or pick a unique one) |
| Pick a region                           | `bom` (Mumbai) or closest to your users |
| Set up a Postgres database?             | **No** — we'll do that separately |
| Set up Upstash Redis?                   | **No** — same           |
| Create .dockerignore from .gitignore?   | **No** (already exists) |

This writes/updates `fly.toml` and creates the app on Fly's side.

## 4. Spin up Postgres

```powershell
fly postgres create --name ummah-db --region bom
```

Choose:
- **Configuration:** "Development - Single node" (free tier)
- **Press enter** for defaults

Then attach it to the app (auto-sets `DATABASE_URL`):

```powershell
fly postgres attach ummah-db --app ummah-backend
```

## 5. Spin up Redis

```powershell
fly redis create --name ummah-cache --region bom
```

Pick "Free" plan. After it provisions, grab the connection URL:

```powershell
fly redis status ummah-cache
```

Copy the line that starts with `redis://default:...`. You'll paste it next.

## 6. Set the remaining secrets

Generate a JWT secret (or pick any 32+ char random string) and set it:

```powershell
fly secrets set --app ummah-backend `
    JWT_SECRET="$(([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([guid]::NewGuid().ToString() + [guid]::NewGuid().ToString()))))" `
    REDIS_URL="redis://default:PASTE_FROM_STEP_5@fly-ummah-cache.upstash.io:6379"
```

The redis module reads `REDIS_HOST` / `REDIS_PORT` / `REDIS_PASSWORD` —
we need to parse the URL OR change the module to accept REDIS_URL.
**Easier path:** set them individually instead:

```powershell
# Parse the redis://default:<password>@<host>:<port> URL by hand
fly secrets set --app ummah-backend `
    REDIS_HOST="fly-ummah-cache.upstash.io" `
    REDIS_PORT="6379" `
    REDIS_PASSWORD="YOUR_PASSWORD_FROM_STEP_5"
```

(Optional, only if you wire OCR later)

```powershell
fly secrets set --app ummah-backend GEMINI_API_KEY="..."
```

## 7. Deploy

```powershell
fly deploy
```

This builds the Dockerfile, runs `npx prisma migrate deploy` as the release
command, and rolls out a new machine. Watch the logs — when you see

```
[Ummah] Server listening on port 8080 (production)
```

your backend is live.

## 8. Sanity check

```powershell
fly status                      # app is "deployed", machine is "started"
curl https://ummah-backend.fly.dev/health
# → {"status":"ok"}
```

## 9. Wire the Flutter app to it

In the Flutter project directory, build with:

```powershell
flutter build apk --release `
    --dart-define=API_BASE_URL=https://ummah-backend.fly.dev
```

## Troubleshooting

**"build failed: npm ci"** — your `package-lock.json` is out of date.
From `Ummah-backend/`, run `npm install` locally, commit the new lockfile,
then `fly deploy` again.

**"release command exited with code 1"** — Prisma couldn't reach Postgres.
Check `fly secrets list --app ummah-backend` — `DATABASE_URL` must be set.
If it's missing, re-run `fly postgres attach`.

**App boots but `/v1/mosques/nearby` returns 500** — Redis isn't connecting.
Test with `fly ssh console --app ummah-backend` then `node -e
"require('ioredis').createClient({host:process.env.REDIS_HOST,port:process.env.REDIS_PORT,password:process.env.REDIS_PASSWORD}).ping().then(console.log)"`.

**Want to wipe and start over** — `fly apps destroy ummah-backend --yes`,
then start at step 3.

## Cost expectations

- App machine: free (256MB shared-cpu, scales to zero when idle)
- Postgres dev cluster: free for 3GB, then $1.94/mo per extra GB
- Upstash Redis free tier: 10,000 commands/day (plenty for testing)
- Bandwidth: 160GB/mo free outbound

If you walk past these limits, Fly will email you. They don't surprise-bill.
