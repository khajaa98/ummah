# Install Ummah on your Android phone

The APK is **already built** at:

```
C:\Users\skhaj\Downloads\Ummah\ummah\build\app\outputs\flutter-apk\app-release.apk
```

(56 MB, debug-signed so it installs without a Play Store account.)

## Option A — USB cable (recommended, 2 min)

1. **Enable USB debugging on your phone** (one-time)
   - Settings → About phone → tap **Build number** 7 times
   - Back → Developer options → toggle **USB debugging** on

2. **Plug your phone into your laptop** with a data-capable USB cable.
   On the phone, tap **Allow** on the "Allow USB debugging?" prompt.

3. **Verify the connection** in PowerShell:

   ```powershell
   C:\Users\skhaj\AppData\Local\Android\Sdk\platform-tools\adb.exe devices
   ```

   You should see one device with state `device` (not `unauthorized`).

4. **Install:**

   ```powershell
   C:\Users\skhaj\AppData\Local\Android\Sdk\platform-tools\adb.exe install -r `
     "C:\Users\skhaj\Downloads\Ummah\ummah\build\app\outputs\flutter-apk\app-release.apk"
   ```

5. Open the app drawer on your phone — **Ummah** should be there.

## Option B — No cable (5 min)

1. Email the APK to yourself (or upload to Google Drive / put it in OneDrive)
   from your laptop.
2. On your phone, download the APK file.
3. The phone will warn "For your security, your phone isn't allowed to
   install unknown apps from this source." Tap **Settings** in that prompt
   and toggle on **Allow from this source** for your browser/email client.
4. Tap the APK → Install.

## What works without the backend

Even with the Fly.io URL not yet live, these screens still function:

- **Onboarding flow** — full 3-slide privacy pitch
- **Qibla compass tab** — magnetometer + figure-8 calibration UX
- **Supporter tab** — RevenueCat falls back to the "Coming soon" stub
- **Prayer tracker** — local-only, persists to SecureStorage

These need the backend:

- **Nearby mosques** — will show the "Connection Error" state
- **Mosque detail timings** — empty state
- **Check-in** — fails with network error

Deploy the backend per `Ummah-backend/FLY_DEPLOY.md` to light those up.

## Heads up

- **Notification permission** — Android 13+ asks for it on first launch.
  Tap **Allow** so prayer reminders work.
- **Location permission** — same, asked when the onboarding "Allow Location &
  Get Started" button is tapped.
- **The 3D mosque viewport** will show a transparent area on the detail
  screen until you drop a GLB file into `assets/models/mosque.glb` and
  rebuild. Everything else still works.
- **Tier visibility** — `flutter_3d_controller` v2 doesn't support
  per-object visibility toggling, so the mosque model renders in full at
  all tiers. The tier counter and upgrade flash still animate when a tier
  threshold is crossed.

## Want to rebuild after code changes?

```powershell
cd C:\Users\skhaj\Downloads\Ummah\ummah
$env:PATH = "C:\Users\skhaj\dev\flutter\bin;$env:PATH"
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
flutter build apk --release --dart-define=API_BASE_URL=https://ummah-backend.fly.dev
```

Then `adb install -r ...` again.
