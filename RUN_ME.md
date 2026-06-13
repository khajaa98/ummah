# Get Ummah running on your Android phone — end-to-end

Read this top to bottom **once**. You'll go from "files in a Downloads folder"
to "tap mosque on phone, see your real backend respond" in about an hour.

## Heads up before you start

- **iPhone is not possible without a Mac.** Period. Apple requires Xcode for
  signing. This guide is Android-only. If you grab a friend's Mac later, the
  Fastlane setup we already wrote will handle the iPhone build.
- **You need an Android phone** running Android 6.0+ (2015 or newer). Borrow
  one from family if you don't have one.
- **You need a credit card** for Fly.io. They won't charge you in the free
  tier, but they require a card to deter abuse.

---

## Step 1 · Install the prereqs (one-time, ~30 min)

### 1a. Flutter SDK

Follow the official Windows guide: <https://docs.flutter.dev/get-started/install/windows>.
The summary:

1. Download the Flutter SDK zip.
2. Unzip to `C:\src\flutter` (not Program Files — needs write access).
3. Add `C:\src\flutter\bin` to your `PATH`.
4. Run `flutter doctor` in a new PowerShell window. Fix any red ✗ items.

You don't need Android Studio for this — just the Android SDK that comes
with Flutter's command-line tools setup.

### 1b. Android command-line tools

```powershell
flutter doctor --android-licenses
# accept all prompts (y)
```

### 1c. Fly CLI

```powershell
iwr https://fly.io/install.ps1 -useb | iex
```

Close & reopen PowerShell so PATH picks up. Verify with `fly version`.

### 1d. ADB on PATH

Comes with the Android SDK. Add `%LOCALAPPDATA%\Android\sdk\platform-tools`
to your PATH. Verify with `adb version`.

---

## Step 2 · Deploy the backend to Fly.io (~15 min)

Open `Ummah-backend/FLY_DEPLOY.md` and follow every step. You'll end with
a URL like `https://ummah-backend.fly.dev`. **Write it down.**

Quick sanity check after deploy:

```powershell
curl https://ummah-backend.fly.dev/health
# → {"status":"ok"}
```

If you see anything else, **stop and fix this first.** No point building the
app if the backend isn't reachable.

### Seed some mosques

The DB is empty after first deploy. Open `Ummah-backend/seed.js` — it
already has a few demo mosques in it. Run it remotely:

```powershell
fly ssh console --app ummah-backend
# inside the SSH session:
node seed.js
exit
```

Verify:

```powershell
curl "https://ummah-backend.fly.dev/v1/mosques/nearby?lat=17.4&lng=78.5&radius_km=50&limit=10" `
    -H "Authorization: Bearer YOUR_TEST_TOKEN"
```

You'll need a JWT — generate one inside the SSH session:

```powershell
fly ssh console --app ummah-backend
node generateToken.js   # this script (check Ummah-backend/) prints a token
```

---

## Step 3 · Scaffold the Flutter project (~5 min)

From the `ummah/` directory (the one containing `files/` and `Ummah-backend/`):

```powershell
cd C:\Users\skhaj\Downloads\Ummah\ummah
powershell -ExecutionPolicy Bypass -File .\scaffold.ps1
```

What this does:
- Runs `flutter create` to generate `android/`, `ios/`, `lib/`, etc.
- Moves every `.dart` file from `files/` into its right place under `lib/`
- Installs the production `pubspec.yaml`
- Drops the Android manifest + permissions
- Runs `flutter pub get`

If something goes wrong, the script tells you where. Fix and re-run — it's
idempotent.

---

## Step 4 · Drop a 3D mosque model (~3 min)

The `Mosque3DViewport` widget loads `assets/models/mosque.glb`. We don't
ship one because asset licensing varies.

Quickest path:

1. Go to <https://sketchfab.com/search?q=mosque&type=models&features=downloadable>
2. Filter to **Free** and **glTF / GLB**.
3. Pick something simple (a low-poly mosque ≤ 5MB).
4. Download the GLB.
5. Save it as **exactly** `C:\Users\skhaj\Downloads\Ummah\ummah\assets\models\mosque.glb`.

If you skip this, the 3D viewport will just show a placeholder shimmer
forever. The rest of the app still works.

---

## Step 5 · Build the APK (~5 min)

```powershell
cd C:\Users\skhaj\Downloads\Ummah\ummah
flutter build apk --release `
    --dart-define=API_BASE_URL=https://ummah-backend.fly.dev
```

Replace the URL with your actual Fly.io URL from Step 2.

The APK ends up at `build\app\outputs\flutter-apk\app-release.apk`.

**Optional dart-defines** (skip if you don't have these yet):
- `--dart-define=SENTRY_DSN=https://...@sentry.io/...`
- `--dart-define=REVENUECAT_ANDROID_KEY=goog_xxx`

Without them, Sentry no-ops and the Supporter screen shows "Coming soon".

---

## Step 6 · Install on your phone (~3 min)

### 6a. Turn on USB debugging

1. On your phone, go to **Settings → About phone**.
2. Tap **Build number** seven times. You'll see "You are now a developer."
3. Go back, open **Developer options**.
4. Enable **USB debugging**.

### 6b. Plug in via USB

1. Connect phone to your laptop with a USB cable.
2. The phone will pop up "Allow USB debugging?" — tap **Allow**.

Verify:

```powershell
adb devices
# Should print:  <serial>   device
```

### 6c. Install

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

That's it. Open the app drawer on your phone, find **Ummah**, tap to launch.

---

## Step 7 · Walk through the app

1. **Onboarding** appears on first launch. Tap "Allow Location & Get Started"
   when prompted, then accept the location permission.
2. **Mosques tab** queries your Fly.io backend with your phone's real GPS.
   You should see the mosques you seeded.
3. Tap a mosque → tap the **star icon** to set it as your home mosque.
4. Pop back. The **Next Prayer Banner** at the top of the mosque list now
   ticks down toward the next prayer in real time.
5. **Qibla tab** — point the phone at the floor while it calibrates, then
   hold it flat. The arrow points toward Mecca.
6. **Supporter tab** — without RevenueCat keys, you see the "Coming soon"
   variant. With keys + a sandbox test account, the real tiers appear.
7. Schedule a fake prayer for 1 minute from now (edit timing in DB):

   ```powershell
   fly postgres connect --app ummah-db
   # in psql:
   UPDATE "PrayerTiming"
   SET asr = to_char(now() + interval '1 minute', 'HH24:MI')
   WHERE "mosqueId" = 'YOUR_FAVOURITE_MOSQUE_ID';
   ```

   In 1 minute, your phone notification fires: "Asr in 5 min · Al-Aqsa Masjid".
   (Yes, the lead time is hard-coded to 5 min, so adjust your test
   accordingly.)

---

## When stuff breaks

**App opens then closes immediately**
→ `adb logcat | Select-String -Pattern "Ummah|FATAL"` — read the stack trace.
Usually a missing asset (no `mosque.glb`) or a bad `API_BASE_URL`.

**"Network error" on mosque list**
→ Your APK was built with the wrong URL. Rebuild with the right
`--dart-define=API_BASE_URL=`.

**No notifications fire**
→ Android 13+: Settings → Apps → Ummah → Notifications must be On.
   Also: some manufacturer ROMs (Xiaomi, Oppo, Huawei) kill background
   alarms aggressively. Search "[your phone model] background battery
   restriction" and whitelist Ummah.

**Qibla arrow spins wildly**
→ Magnetometer is uncalibrated. The app shows a Figure-8 overlay when this
   happens — move the phone in a figure-8 motion until it goes away.
   If your phone has no magnetometer (most tablets), it just shows an error.

**`flutter build apk` fails on "minSdk"**
→ Make sure scaffold.ps1 ran successfully. The Android manifest + build.gradle
   we ship require minSdk 23, but the default scaffold uses 21.

---

## What's next

- Hook up **RevenueCat** — open <https://app.revenuecat.com>, create an app,
  paste the Android key into the build command's `--dart-define`.
- Hook up **Sentry** — <https://sentry.io>, create a Flutter project, paste
  the DSN.
- When you have access to a Mac (or rent MacInCloud for a day), the
  `fastlane/Fastfile` we already wrote will build the iOS version too.

You're 95% of the way to V1. Last 5% is a Mac.
