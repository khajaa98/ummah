# scaffold.ps1
# =============================================================================
# Turns the flat `files/` directory into a real Flutter project structure.
#
# Run this ONCE, from the `ummah/` directory:
#   cd C:\Users\skhaj\Downloads\Ummah\ummah
#   powershell -ExecutionPolicy Bypass -File .\scaffold.ps1
#
# What it does:
#   1. Runs `flutter create` to generate android/, ios/, lib/, test/, etc.
#   2. Moves every .dart file from files/ to its real path under lib/, matching
#      the import statements at the top of each file.
#   3. Overwrites pubspec.yaml with the version that has all our deps.
#   4. Drops Android/iOS manifests + permissions from files/android-config/.
#   5. Creates assets/models/ for the GLB placeholder.
#
# Idempotent: re-running won't damage anything; flutter create skips existing
# files, and Move-Item -Force overwrites lib/ entries on a re-run.
# =============================================================================

param(
    [string]$ProjectDir = "$PSScriptRoot",
    [string]$AppName    = "ummah",
    [string]$Org        = "app.ummah"
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 0. Sanity check
# ---------------------------------------------------------------------------

Write-Host "==> Ummah scaffold script" -ForegroundColor Cyan
Write-Host "    Project dir: $ProjectDir"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "flutter is not on your PATH. Install Flutter first: https://docs.flutter.dev/get-started/install/windows"
    exit 1
}

if (-not (Test-Path "$ProjectDir\files")) {
    Write-Error "Expected to find a 'files\' directory under $ProjectDir. Are you running this from the right place?"
    exit 1
}

# ---------------------------------------------------------------------------
# 1. Scaffold the Flutter project (in-place)
# ---------------------------------------------------------------------------

Write-Host "==> Running flutter create" -ForegroundColor Cyan
Push-Location $ProjectDir
try {
    if (-not (Test-Path "$ProjectDir\pubspec.yaml")) {
        # First-time scaffold
        flutter create --org $Org --project-name $AppName --platforms=android,ios `
            --no-overwrite .
    } else {
        Write-Host "    pubspec.yaml already exists, skipping flutter create."
    }
} finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# 2. File-to-path mapping
#    Source file (under files/) -> Destination path (under lib/)
# ---------------------------------------------------------------------------

$map = @{
    # ---- entry ----
    'main.dart'                          = 'lib\main.dart'

    # ---- core ----
    'app_exception.dart'                 = 'lib\core\errors\app_exception.dart'
    'api_constants.dart'                 = 'lib\core\constants\api_constants.dart'
    'dynamic_theme_provider.dart'        = 'lib\core\providers\dynamic_theme_provider.dart'
    'app_themes.dart'                    = 'lib\core\theme\app_themes.dart'
    'prayer_phase.dart'                  = 'lib\core\theme\prayer_phase.dart'
    'prayer_phase_provider.dart'         = 'lib\core\providers\prayer_phase_provider.dart'

    # ---- services ----
    'token_service.dart'                 = 'lib\services\auth\token_service.dart'
    'location_service.dart'              = 'lib\services\location\location_service.dart'
    'notification_service.dart'          = 'lib\services\notifications\notification_service.dart'
    'purchases_service.dart'             = 'lib\services\purchases\purchases_service.dart'
    'sentry_init.dart'                   = 'lib\services\telemetry\sentry_init.dart'

    # ---- mosques feature ----
    'mosque.dart'                        = 'lib\features\mosques\data\models\mosque_model.dart'
    'prayer_timing.dart'                 = 'lib\features\mosques\data\models\prayer_timing.dart'
    'mosque_repository.dart'             = 'lib\features\mosques\data\repositories\mosque_repository.dart'
    'nearby_mosques_provider.dart'       = 'lib\features\mosques\presentation\providers\nearby_mosques_provider.dart'
    'prayer_timings_provider.dart'       = 'lib\features\mosques\presentation\providers\prayer_timings_provider.dart'
    'favourite_mosque_provider.dart'     = 'lib\features\mosques\presentation\providers\favourite_mosque_provider.dart'
    'community_checkin_provider.dart'    = 'lib\features\mosques\presentation\providers\community_checkin_provider.dart'
    'mosque_3d_nodes.dart'               = 'lib\features\mosques\presentation\constants\mosque_3d_nodes.dart'
    'mosque_3d_viewport.dart'            = 'lib\features\mosques\presentation\widgets\mosque_3d_viewport.dart'
    'mosque_card.dart'                   = 'lib\features\mosques\presentation\widgets\mosque_card.dart'
    'nearby_mosques_screen.dart'         = 'lib\features\mosques\presentation\screens\nearby_mosques_screen.dart'
    'mosque_detail_screen.dart'          = 'lib\features\mosques\presentation\screens\mosque_detail_screen.dart'

    # ---- prayer feature ----
    'prayer_tracker_state.dart'          = 'lib\features\prayer\state\prayer_tracker_state.dart'
    'prayer_tracker_provider.dart'       = 'lib\features\prayer\providers\prayer_tracker_provider.dart'
    'prayer_tracker_widget.dart'         = 'lib\widgets\prayer_tracker_widget.dart'
    'next_prayer_banner.dart'            = 'lib\features\prayer\next_prayer_banner.dart'

    # ---- onboarding / qibla / settings ----
    'onboarding_screen.dart'             = 'lib\features\onboarding\onboarding_screen.dart'
    'qibla_screen.dart'                  = 'lib\features\qibla\qibla_screen.dart'
    'supporter_screen.dart'              = 'lib\features\settings\supporter_screen.dart'

    # ---- tests ----
    'mosque_repository_test.dart'        = 'test\features\mosques\data\repositories\mosque_repository_test.dart'
    'prayer_tracker_test.dart'           = 'test\features\prayer\prayer_tracker_test.dart'

    # ---- integration tests ----
    'screenshots_test.dart'              = 'integration_test\screenshots_test.dart'
}

# ---------------------------------------------------------------------------
# 3. Move every file into place
# ---------------------------------------------------------------------------

Write-Host "==> Moving .dart files into lib/" -ForegroundColor Cyan

foreach ($entry in $map.GetEnumerator()) {
    $src  = Join-Path "$ProjectDir\files" $entry.Key
    $dest = Join-Path $ProjectDir         $entry.Value

    if (-not (Test-Path $src)) {
        Write-Host "    [skip] $($entry.Key)  (not in files/)" -ForegroundColor DarkYellow
        continue
    }

    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    Copy-Item -Path $src -Destination $dest -Force
    Write-Host "    [ok] $($entry.Key)  ->  $($entry.Value)"
}

# ---------------------------------------------------------------------------
# 4. Replace generated pubspec.yaml with ours
# ---------------------------------------------------------------------------

Write-Host "==> Installing pubspec.yaml" -ForegroundColor Cyan
Copy-Item -Path "$ProjectDir\files\pubspec.yaml" `
          -Destination "$ProjectDir\pubspec.yaml" `
          -Force

# ---------------------------------------------------------------------------
# 5. Drop Android platform files into place
# ---------------------------------------------------------------------------

$androidCfg = "$ProjectDir\files\android-config"
if (Test-Path $androidCfg) {
    Write-Host "==> Copying Android config" -ForegroundColor Cyan
    Copy-Item -Path "$androidCfg\AndroidManifest.xml" `
              -Destination "$ProjectDir\android\app\src\main\AndroidManifest.xml" -Force
    Copy-Item -Path "$androidCfg\network_security_config.xml" `
              -Destination "$ProjectDir\android\app\src\main\res\xml\network_security_config.xml" -Force
    Copy-Item -Path "$androidCfg\build.gradle" `
              -Destination "$ProjectDir\android\app\build.gradle" -Force
}

# ---------------------------------------------------------------------------
# 6. Create asset directories
# ---------------------------------------------------------------------------

Write-Host "==> Creating assets/ directories" -ForegroundColor Cyan
New-Item -ItemType Directory -Path "$ProjectDir\assets\models" -Force | Out-Null

if (-not (Test-Path "$ProjectDir\assets\models\mosque.glb")) {
    Write-Host "    [warn] No mosque.glb found. Drop a GLB file at:" -ForegroundColor Yellow
    Write-Host "             $ProjectDir\assets\models\mosque.glb"
    Write-Host "           Sources: https://sketchfab.com/search?q=mosque&type=models  (free filter, GLB download)"
}

# ---------------------------------------------------------------------------
# 7. flutter pub get
# ---------------------------------------------------------------------------

Write-Host "==> Running flutter pub get" -ForegroundColor Cyan
Push-Location $ProjectDir
try {
    flutter pub get
} finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "==> Scaffold complete." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Deploy backend:   see Ummah-backend\FLY_DEPLOY.md"
Write-Host "  2. Drop a mosque.glb: see assets\models\"
Write-Host "  3. Build APK:        flutter build apk --dart-define=API_BASE_URL=https://your-fly-url.fly.dev"
Write-Host "  4. Install on phone: see RUN_ME.md"
Write-Host ""
