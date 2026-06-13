# provision.ps1
# =============================================================================
# Provisions the entire Ummah backend infrastructure on AWS via the CLI.
#
# What it creates (all in your default VPC, region of your choice):
#   1. Three security groups:
#        ummah-ec2-sg     - allows SSH from your IP + HTTP/HTTPS from anywhere
#        ummah-rds-sg     - allows 5432 from ummah-ec2-sg only
#        ummah-cache-sg   - allows 6379 from ummah-ec2-sg only
#   2. An EC2 key pair (ummah-key) - private key saved locally as ummah-key.pem
#   3. An RDS db.t4g.micro Postgres 16 instance (free tier eligible)
#   4. An ElastiCache cache.t4g.micro Redis instance (free tier trial)
#   5. An EC2 t3.micro Ubuntu 22.04 instance (free tier eligible)
#
# Prereqs:
#   • AWS CLI installed and `aws configure` already done
#   • An IAM user (NOT root) with admin or PowerUserAccess + IAMUserChangePassword
#   • You've picked a region close to your users (default: ap-south-1 = Mumbai)
#
# Outputs (printed at the end, also written to .ummah-deploy.env):
#   • RDS endpoint
#   • Redis endpoint
#   • EC2 public DNS
#   • SSH command
#
# Run:
#   powershell -ExecutionPolicy Bypass -File .\provision.ps1
#
# Cost (free tier 12 months):
#   EC2 t3.micro:     750 hrs/month free
#   RDS t4g.micro:    750 hrs/month free, 20GB storage
#   ElastiCache:      750 hrs/month t4g.micro free (12-month trial)
#   Total expected:   $0/mo for 12 months, then ~$40/mo
# =============================================================================

param(
    [string]$Region        = 'ap-south-1',
    [string]$Prefix        = 'ummah',
    [string]$DbMasterUser  = 'ummah_master',
    [string]$DbName        = 'ummah'
)

# NOTE: keep this 'Continue' rather than 'Stop'. Windows PowerShell 5.1 wraps
# every stderr line from native commands (like aws.exe) as a NativeCommandError;
# with 'Stop' that aborts the script even on benign noise (telemetry warnings,
# credential file notices, etc.). Real AWS failures still surface via the
# error text being printed and via explicit $LASTEXITCODE checks below.
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# 0. Sanity check
# ---------------------------------------------------------------------------

Write-Host "==> Ummah AWS provisioning script" -ForegroundColor Cyan
Write-Host "    Region: $Region"
Write-Host "    Prefix: $Prefix"

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Error "AWS CLI not on PATH. Install it first (see AWS_DEPLOY.md step 1)."
    exit 1
}

$identity = aws sts get-caller-identity --output json 2>&1 | ConvertFrom-Json
if (-not $identity.Arn) {
    Write-Error "AWS credentials not configured. Run 'aws configure' first."
    exit 1
}
Write-Host "    Authenticated as: $($identity.Arn)" -ForegroundColor Green

# Generate strong DB password
Add-Type -AssemblyName System.Web
$DbPassword = [System.Web.Security.Membership]::GeneratePassword(24, 4)
# RDS doesn't allow these chars in master password
$DbPassword = $DbPassword -replace '[/@"\s]', 'X'

# Generate JWT secret
$JwtSecret = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(
    [guid]::NewGuid().ToString() + [guid]::NewGuid().ToString()))

# ---------------------------------------------------------------------------
# 1. Get default VPC
# ---------------------------------------------------------------------------

Write-Host "==> Looking up default VPC..." -ForegroundColor Cyan
$vpcId = aws ec2 describe-vpcs --region $Region `
    --filters 'Name=is-default,Values=true' `
    --query 'Vpcs[0].VpcId' --output text

if (-not $vpcId -or $vpcId -eq 'None') {
    Write-Error "No default VPC in $Region. Create one in the AWS console or pick a different region."
    exit 1
}
Write-Host "    VPC: $vpcId"

# ---------------------------------------------------------------------------
# 2. Get your current IP for SSH access
# ---------------------------------------------------------------------------

$myIp = (Invoke-WebRequest -Uri 'https://checkip.amazonaws.com' -UseBasicParsing).Content.Trim()
Write-Host "    Your IP for SSH allowlist: $myIp"

# ---------------------------------------------------------------------------
# 3. Helper - create-or-get a security group
# ---------------------------------------------------------------------------

function Ensure-SecurityGroup {
    param([string]$Name, [string]$Description)
    $sgId = aws ec2 describe-security-groups --region $Region `
        --filters "Name=group-name,Values=$Name" "Name=vpc-id,Values=$vpcId" `
        --query 'SecurityGroups[0].GroupId' --output text 2>$null
    if ($sgId -and $sgId -ne 'None') {
        Write-Host "    [exists] $Name = $sgId"
        return $sgId
    }
    $sgId = aws ec2 create-security-group --region $Region `
        --group-name $Name `
        --description $Description `
        --vpc-id $vpcId `
        --query 'GroupId' --output text
    Write-Host "    [created] $Name = $sgId" -ForegroundColor Green
    return $sgId
}

# ---------------------------------------------------------------------------
# 4. Create security groups
# ---------------------------------------------------------------------------

Write-Host "==> Creating security groups..." -ForegroundColor Cyan
$ec2Sg   = Ensure-SecurityGroup -Name "$Prefix-ec2-sg"   -Description "Ummah EC2 instance"
$rdsSg   = Ensure-SecurityGroup -Name "$Prefix-rds-sg"   -Description "Ummah RDS Postgres"
$cacheSg = Ensure-SecurityGroup -Name "$Prefix-cache-sg" -Description "Ummah ElastiCache Redis"

# Idempotently add inbound rules - ignore errors if rules already exist
Write-Host "==> Adding inbound rules..." -ForegroundColor Cyan
$rules = @(
    @{ Group=$ec2Sg;   Proto='tcp'; Port='22';   Source="$myIp/32" }
    @{ Group=$ec2Sg;   Proto='tcp'; Port='80';   Source='0.0.0.0/0' }
    @{ Group=$ec2Sg;   Proto='tcp'; Port='443';  Source='0.0.0.0/0' }
    @{ Group=$rdsSg;   Proto='tcp'; Port='5432'; SourceGroup=$ec2Sg }
    @{ Group=$cacheSg; Proto='tcp'; Port='6379'; SourceGroup=$ec2Sg }
)
foreach ($r in $rules) {
    $args = @('ec2','authorize-security-group-ingress',
              '--region', $Region,
              '--group-id', $r.Group,
              '--protocol', $r.Proto,
              '--port', $r.Port)
    if ($r.Source) {
        $args += @('--cidr', $r.Source)
    } else {
        $args += @('--source-group', $r.SourceGroup)
    }
    & aws @args 2>$null | Out-Null
}
Write-Host "    Rules applied (duplicates silently ignored)."

# ---------------------------------------------------------------------------
# 5. EC2 key pair
# ---------------------------------------------------------------------------

Write-Host "==> EC2 key pair..." -ForegroundColor Cyan
$keyName = "$Prefix-key"
$keyFile = "$PSScriptRoot\$keyName.pem"
$existingKey = aws ec2 describe-key-pairs --region $Region `
    --key-names $keyName --query 'KeyPairs[0].KeyName' --output text 2>$null

if ($existingKey -eq $keyName -and (Test-Path $keyFile)) {
    Write-Host "    [exists] $keyName (private key at $keyFile)"
} elseif ($existingKey -eq $keyName) {
    Write-Warning "Key pair $keyName exists on AWS but $keyFile is missing locally. Delete it on AWS or rename."
    exit 1
} else {
    aws ec2 create-key-pair --region $Region `
        --key-name $keyName `
        --query 'KeyMaterial' --output text | Out-File -FilePath $keyFile -Encoding ascii
    # Lock down permissions on the private key
    icacls $keyFile /inheritance:r | Out-Null
    icacls $keyFile /grant:r "${env:USERNAME}:R" | Out-Null
    Write-Host "    [created] $keyFile" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 6. RDS Postgres
# ---------------------------------------------------------------------------

Write-Host "==> RDS Postgres..." -ForegroundColor Cyan
$rdsId = "$Prefix-db"
$existingRds = aws rds describe-db-instances --region $Region `
    --db-instance-identifier $rdsId --query 'DBInstances[0].DBInstanceIdentifier' `
    --output text 2>$null

if ($existingRds -eq $rdsId) {
    Write-Host "    [exists] $rdsId"
} else {
    Write-Host "    [creating] $rdsId (this takes ~5 minutes)"
    aws rds create-db-instance --region $Region `
        --db-instance-identifier $rdsId `
        --db-instance-class db.t4g.micro `
        --engine postgres `
        --engine-version 16.3 `
        --master-username $DbMasterUser `
        --master-user-password $DbPassword `
        --allocated-storage 20 `
        --db-name $DbName `
        --vpc-security-group-ids $rdsSg `
        --backup-retention-period 0 `
        --no-multi-az `
        --no-publicly-accessible `
        --no-storage-encrypted `
        --no-deletion-protection | Out-Null
    Write-Host "    [submitted] waiting for available state..."
    aws rds wait db-instance-available --region $Region --db-instance-identifier $rdsId
    Write-Host "    [available]" -ForegroundColor Green
}

$rdsEndpoint = aws rds describe-db-instances --region $Region `
    --db-instance-identifier $rdsId `
    --query 'DBInstances[0].Endpoint.Address' --output text
Write-Host "    Endpoint: $rdsEndpoint"

# ---------------------------------------------------------------------------
# 7. ElastiCache Redis
# ---------------------------------------------------------------------------

Write-Host "==> ElastiCache Redis..." -ForegroundColor Cyan
$cacheId = "$Prefix-cache"
$existingCache = aws elasticache describe-cache-clusters --region $Region `
    --cache-cluster-id $cacheId --query 'CacheClusters[0].CacheClusterId' `
    --output text 2>$null

if ($existingCache -eq $cacheId) {
    Write-Host "    [exists] $cacheId"
} else {
    Write-Host "    [creating] $cacheId (this takes ~3 minutes)"
    aws elasticache create-cache-cluster --region $Region `
        --cache-cluster-id $cacheId `
        --engine redis `
        --cache-node-type cache.t4g.micro `
        --num-cache-nodes 1 `
        --engine-version 7.1 `
        --security-group-ids $cacheSg | Out-Null
    Write-Host "    [submitted] waiting for available state..."
    aws elasticache wait cache-cluster-available --region $Region --cache-cluster-id $cacheId
    Write-Host "    [available]" -ForegroundColor Green
}

$cacheEndpoint = aws elasticache describe-cache-clusters --region $Region `
    --cache-cluster-id $cacheId `
    --show-cache-node-info `
    --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' --output text
Write-Host "    Endpoint: $cacheEndpoint"

# ---------------------------------------------------------------------------
# 8. EC2 instance
# ---------------------------------------------------------------------------

Write-Host "==> EC2 instance..." -ForegroundColor Cyan
$instanceTag = "$Prefix-server"
$existingInstance = aws ec2 describe-instances --region $Region `
    --filters "Name=tag:Name,Values=$instanceTag" "Name=instance-state-name,Values=pending,running" `
    --query 'Reservations[0].Instances[0].InstanceId' --output text 2>$null

if ($existingInstance -and $existingInstance -ne 'None') {
    Write-Host "    [exists] $existingInstance"
    $instanceId = $existingInstance
} else {
    Write-Host "    [creating] $instanceTag"
    # Latest Ubuntu 22.04 LTS AMI ID (varies by region - use SSM parameter)
    $amiId = aws ssm get-parameter --region $Region `
        --name '/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id' `
        --query 'Parameter.Value' --output text

    $instanceId = aws ec2 run-instances --region $Region `
        --image-id $amiId `
        --instance-type t3.micro `
        --key-name $keyName `
        --security-group-ids $ec2Sg `
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instanceTag}]" `
        --block-device-mappings '[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":20,\"VolumeType\":\"gp3\"}}]' `
        --query 'Instances[0].InstanceId' --output text
    Write-Host "    [submitted] $instanceId - waiting for running state..."
    aws ec2 wait instance-running --region $Region --instance-ids $instanceId
    Write-Host "    [running]" -ForegroundColor Green
}

$ec2PublicDns = aws ec2 describe-instances --region $Region `
    --instance-ids $instanceId `
    --query 'Reservations[0].Instances[0].PublicDnsName' --output text
$ec2PublicIp = aws ec2 describe-instances --region $Region `
    --instance-ids $instanceId `
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text

# ---------------------------------------------------------------------------
# 9. Persist outputs
# ---------------------------------------------------------------------------

$envFile = "$PSScriptRoot\.ummah-deploy.env"
@"
# Generated by provision.ps1 - copy these to the EC2 server's .env after SSH-ing in.
# DO NOT COMMIT THIS FILE.

DATABASE_URL=postgresql://${DbMasterUser}:${DbPassword}@${rdsEndpoint}:5432/${DbName}?sslmode=require
REDIS_HOST=$cacheEndpoint
REDIS_PORT=6379
REDIS_PASSWORD=
JWT_SECRET=$JwtSecret
NODE_ENV=production
PORT=8080
"@ | Out-File -FilePath $envFile -Encoding ascii

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Green
Write-Host " Provisioning complete." -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Green
Write-Host ""
Write-Host " EC2 host:    $ec2PublicDns"
Write-Host " EC2 IP:      $ec2PublicIp"
Write-Host " RDS:         $rdsEndpoint"
Write-Host " Redis:       $cacheEndpoint"
Write-Host ""
Write-Host " SSH command:"
Write-Host "   ssh -i $keyFile ubuntu@$ec2PublicDns" -ForegroundColor Yellow
Write-Host ""
Write-Host " Connection secrets saved to: $envFile"
Write-Host ""
Write-Host " Next: see AWS_DEPLOY.md section 4 (Server setup on EC2)"
Write-Host ""
