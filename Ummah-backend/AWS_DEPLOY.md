# Ummah backend on AWS — EC2 + RDS + ElastiCache (free tier)

End-to-end deploy guide. Estimated time: **2 hours** the first time you do it.
After year 1, expect **~$40/mo** unless you stop the instances.

## What you'll end up with

- A managed Postgres 16 on **RDS** (`db.t4g.micro`, 20 GB storage)
- A managed Redis 7 on **ElastiCache** (`cache.t4g.micro`)
- An Ubuntu 22.04 server on **EC2** (`t3.micro`) running the Express app under
  PM2, fronted by Nginx + Let's Encrypt
- A free HTTPS subdomain via **DuckDNS** — e.g. `ummah-skhaj.duckdns.org`
- The Flutter app talking to it over real TLS

## ⚠️ Cost discipline (read first)

AWS has burned thousands of beginners. Three rules:

1. **Set a billing alert before you do anything else.** Console → Billing →
   Budgets → Create budget → "Zero spend budget". You'll get an email the
   moment any chargeable resource starts.
2. **Stay in one region.** This guide uses `ap-south-1` (Mumbai). Resources in
   other regions don't share free tier hours.
3. **When you're done testing, delete or stop everything.** Stopping an EC2
   instance is free (storage still costs ~$2/mo for 20 GB EBS). Stopping
   RDS is free for up to 7 days, then it auto-starts. ElastiCache CANNOT be
   stopped — you must delete the cluster to stop paying.

The teardown command is at the bottom of this file. Use it.

---

## Step 0 · AWS CLI install (one-time, ~5 min)

On Windows in PowerShell:

```powershell
winget install --id=Amazon.AWSCLI -e --accept-source-agreements --accept-package-agreements
```

Close + reopen PowerShell. Verify:

```powershell
aws --version
# aws-cli/2.x.x Python/3.x.x Windows/...
```

## Step 1 · IAM user for deployment (one-time, ~10 min)

Don't use your AWS root account for anything except billing. Create a
deployment-scoped IAM user.

1. AWS Console → **IAM** → **Users** → **Create user**
2. Name: `ummah-deployer`
3. Tick **Provide user access to the AWS Management Console** — *off*
4. Next → **Attach policies directly**
5. Tick **AdministratorAccess** (we'll narrow this later for production)
6. Next → **Create user**
7. Open the user → **Security credentials** → **Create access key**
8. Use case: **Command Line Interface (CLI)** → tick confirmation → Next
9. Tag: `deploy`
10. **Download .csv** — this is your one chance to save the secret key

Then configure CLI:

```powershell
aws configure
# AWS Access Key ID:     <paste from CSV>
# AWS Secret Access Key: <paste from CSV>
# Default region name:   ap-south-1
# Default output format: json
```

Verify:

```powershell
aws sts get-caller-identity
# Should print your user ARN
```

## Step 2 · DuckDNS subdomain (one-time, ~3 min)

We need a real hostname so Let's Encrypt can issue an SSL cert.

1. Go to <https://www.duckdns.org>
2. Sign in with Google / GitHub
3. Under "domains", type a unique name (e.g. `ummah-skhaj`) → **add domain**
4. Note your **token** at the top of the page

Don't fill in the IP field — `server-setup.sh` will do that automatically
once EC2 is up.

## Step 3 · Provision AWS infrastructure (~10 min wall time, mostly waiting)

From `Ummah-backend/`:

```powershell
cd C:\Users\skhaj\Downloads\Ummah\ummah\Ummah-backend
powershell -ExecutionPolicy Bypass -File .\provision.ps1
```

What this does (see the script's header comment for full details):

- Looks up the default VPC in `ap-south-1`
- Creates three security groups (EC2, RDS, ElastiCache)
- Locks RDS + ElastiCache so only the EC2 SG can reach them
- Allows SSH (port 22) **only from your current IP** (auto-detected) +
  HTTP/HTTPS from anywhere
- Generates an SSH key pair, saves the private key as `ummah-key.pem`
- Launches RDS Postgres (~5 min)
- Launches ElastiCache Redis (~3 min)
- Launches an EC2 t3.micro Ubuntu instance (~30 sec)
- Writes connection strings + a generated JWT secret to `.ummah-deploy.env`

At the end it prints something like:

```
==============================================================
 Provisioning complete.
==============================================================

 EC2 host:    ec2-3-110-x-x.ap-south-1.compute.amazonaws.com
 EC2 IP:      3.110.x.x
 RDS:         ummah-db.xxxxxxxxxxxx.ap-south-1.rds.amazonaws.com
 Redis:       ummah-cache.xxxxxx.ng.0001.aps1.cache.amazonaws.com

 SSH command:
   ssh -i ...\ummah-key.pem ubuntu@ec2-3-110-x-x.ap-south-1.compute.amazonaws.com
```

**Note the SSH command** — you'll use it in step 4.

### If something fails mid-way

The script is idempotent. Re-run it; existing resources are detected and
reused. If a particular resource is stuck in a weird state, delete it via
the AWS console and re-run.

## Step 4 · Upload the backend source to EC2 (~2 min)

From your laptop:

```powershell
cd C:\Users\skhaj\Downloads\Ummah\ummah\Ummah-backend

# Get the EC2 DNS the provision script printed
$ec2 = "ec2-XXX-XXX-XXX-XXX.ap-south-1.compute.amazonaws.com"

# Copy everything except node_modules + .env + the key itself
$exclude = @('node_modules','*.pem','.ummah-deploy.env','.env')
$src = Get-ChildItem -Force | Where-Object { $exclude -notcontains $_.Name -and $_.Name -notlike '*.pem' }

# SCP — Windows 10+ has scp.exe built in via OpenSSH Client
scp -i .\ummah-key.pem -r $src.FullName ubuntu@${ec2}:/tmp/ummah/
```

(If `scp` isn't found: `Settings → Apps → Optional Features → Add → "OpenSSH Client"`.)

## Step 5 · SSH in and run the setup script (~10 min)

```powershell
ssh -i .\ummah-key.pem ubuntu@$ec2
```

(Type `yes` to accept the fingerprint on first connect.)

Once you're on the instance:

```bash
sudo mkdir -p /srv/ummah/app
sudo mv /tmp/ummah/* /srv/ummah/app/
sudo chown -R ummah:ummah /srv/ummah/app 2>/dev/null || true
sudo bash /srv/ummah/app/server-setup.sh
```

The script will ask you for:

| Prompt | Paste from |
|---|---|
| DuckDNS subdomain | Step 2 |
| DuckDNS token | Step 2 |
| Email for Let's Encrypt | Your real email |
| `DATABASE_URL` | `.ummah-deploy.env` line 1 |
| `REDIS_HOST` | `.ummah-deploy.env` |
| `REDIS_PORT` | press Enter (defaults to 6379) |
| `REDIS_PASSWORD` | press Enter (ElastiCache without auth) |
| `JWT_SECRET` | `.ummah-deploy.env` |

Open `.ummah-deploy.env` on your laptop in a text editor and copy the
values one at a time.

The script will take ~5 minutes. At the end it prints:

```
============================================================
 Ummah backend is LIVE.
============================================================

 Public URL:   https://ummah-skhaj.duckdns.org
 Health:       https://ummah-skhaj.duckdns.org/health
```

Verify from your laptop:

```powershell
curl https://ummah-skhaj.duckdns.org/health
# → {"status":"ok"}
```

## Step 6 · Rebuild the APK pointing at AWS

From the Flutter project root:

```powershell
cd C:\Users\skhaj\Downloads\Ummah\ummah
$env:PATH = "C:\Users\skhaj\dev\flutter\bin;$env:PATH"
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
flutter build apk --release `
    --dart-define=API_BASE_URL=https://ummah-skhaj.duckdns.org
```

Then install on your phone per `SIDELOAD.md`.

---

## Day-2 operations

### View logs

```bash
sudo -u ummah pm2 logs ummah --lines 100
```

### Restart after a code change

```bash
# Re-upload source
scp -i .\ummah-key.pem -r * ubuntu@${ec2}:/tmp/ummah-new/
ssh -i .\ummah-key.pem ubuntu@$ec2

# On the server:
sudo cp -r /tmp/ummah-new/* /srv/ummah/app/
sudo chown -R ummah:ummah /srv/ummah/app
sudo -u ummah bash -c "cd /srv/ummah/app && npm ci --omit=dev && npx prisma migrate deploy"
sudo -u ummah pm2 restart ummah
```

### Connect to the database

```bash
# From inside the EC2 instance:
psql "$(grep DATABASE_URL /srv/ummah/app/.env | cut -d= -f2-)"
```

### Connect to Redis

```bash
redis-cli -h ${REDIS_HOST} -p 6379
```

### Renew SSL cert

`certbot.timer` runs twice daily and auto-renews when < 30 days remain.
No action needed.

---

## Teardown — stop paying

When you're done testing, run this from your laptop:

```powershell
$Region = 'ap-south-1'
$Prefix = 'ummah'

# 1. Terminate EC2
$ec2Ids = aws ec2 describe-instances --region $Region `
    --filters "Name=tag:Name,Values=$Prefix-server" "Name=instance-state-name,Values=running,stopped" `
    --query 'Reservations[].Instances[].InstanceId' --output text
if ($ec2Ids) { aws ec2 terminate-instances --region $Region --instance-ids $ec2Ids.Split() }

# 2. Delete RDS (skip final snapshot — it's a test DB)
aws rds delete-db-instance --region $Region `
    --db-instance-identifier "$Prefix-db" `
    --skip-final-snapshot `
    --delete-automated-backups

# 3. Delete ElastiCache (cannot be stopped, must be deleted)
aws elasticache delete-cache-cluster --region $Region `
    --cache-cluster-id "$Prefix-cache"

# 4. Wait for RDS + ElastiCache to fully disappear (~5 min each)
aws rds wait db-instance-deleted --region $Region --db-instance-identifier "$Prefix-db"
aws elasticache wait cache-cluster-deleted --region $Region --cache-cluster-id "$Prefix-cache"

# 5. Delete security groups (must come after the resources using them)
foreach ($sg in @("$Prefix-ec2-sg","$Prefix-rds-sg","$Prefix-cache-sg")) {
    $id = aws ec2 describe-security-groups --region $Region `
        --filters "Name=group-name,Values=$sg" `
        --query 'SecurityGroups[0].GroupId' --output text 2>$null
    if ($id -and $id -ne 'None') {
        aws ec2 delete-security-group --region $Region --group-id $id
    }
}

# 6. Delete the key pair (private key file stays on your machine — feel free to keep)
aws ec2 delete-key-pair --region $Region --key-name "$Prefix-key"

Write-Host "Teardown complete. Verify in the AWS console that nothing remains."
```

---

## Troubleshooting

**"AccessDenied" running provision.ps1**
Your IAM user lacks permissions. Easiest fix: temporarily attach
`AdministratorAccess`. Long-term: see the Production hardening section.

**RDS create fails with "InvalidParameterCombination: DB instance class…"**
`db.t4g.micro` isn't available in every region. Try `db.t3.micro` (also free
tier eligible) by editing the script.

**Certbot fails with "Connection refused"**
DuckDNS hasn't propagated yet. Wait 60 seconds and re-run
`sudo certbot --nginx --domains ummah-skhaj.duckdns.org`.

**Curl from laptop hangs**
The security group only allows your IP for SSH (port 22), and 80/443 from
anywhere. If your home IP changed (mobile hotspot, VPN), update the SSH
rule:

```powershell
$Region = 'ap-south-1'
$sgId = aws ec2 describe-security-groups --region $Region `
    --filters "Name=group-name,Values=ummah-ec2-sg" `
    --query 'SecurityGroups[0].GroupId' --output text
# Replace OLD_IP/32 with the IP that was authorized; then:
$newIp = (Invoke-WebRequest -Uri 'https://checkip.amazonaws.com' -UseBasicParsing).Content.Trim()
aws ec2 authorize-security-group-ingress --region $Region --group-id $sgId `
    --protocol tcp --port 22 --cidr "$newIp/32"
```

**Node app crashes with "ECONNREFUSED 127.0.0.1:6379"**
The Redis client is hitting localhost instead of ElastiCache. Check
`/srv/ummah/app/.env` — `REDIS_HOST` must be the ElastiCache endpoint, not
empty. Then `sudo -u ummah pm2 restart ummah`.

**Prayer notification scheduling failing on phone**
Backend health unrelated; check `adb logcat | Select-String Ummah` on the
phone for the actual error.

---

## Production hardening (optional, do later)

1. **Tighten the IAM policy** — replace `AdministratorAccess` with a custom
   policy that only allows `ec2:*`, `rds:*`, `elasticache:*` on resources
   tagged `Project=Ummah`. Cuts blast radius on credential leak.
2. **Move RDS to multi-AZ** — when you have paying users. ~2x cost but
   survives an AZ outage.
3. **Use Secrets Manager** instead of `.env` files on disk. Adds $0.40/mo
   per secret.
4. **CloudFront in front of EC2** — for users far from `ap-south-1`,
   CloudFront caches static responses + provides DDoS protection. ~$5/mo
   for hobby usage.
5. **Set up Route 53** — when you buy a real domain, point it at the EC2
   IP (and delete the DuckDNS subdomain).
6. **CloudWatch alarms** — alert when EC2 CPU > 80%, RDS storage > 80%,
   or 5xx error rate > 1%.

---

## Why not Lightsail / App Runner?

Lightsail bundles EC2 + a managed DB at fixed prices ($5 + $15 = $20/mo).
Simpler, but **no free tier**, and you can't add ElastiCache (Lightsail
doesn't offer Redis).

App Runner is the equivalent of Fly's container model on AWS. Fast to
deploy but ~$25/mo just for the compute, plus RDS + ElastiCache on top.
Worth it if you grow past prototype, not now.

EC2 free tier wins for a 12-month learning runway. After that, re-evaluate.
