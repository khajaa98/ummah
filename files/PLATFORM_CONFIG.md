# Platform Configuration for Ummah
# ============================================================
# These changes must be applied manually to the native project
# files after running `flutter create .` or merging into an
# existing project.
# ============================================================


## Android — android/app/src/main/AndroidManifest.xml

Add inside <manifest>:

  <!-- Coarse only: used for quick initial map center -->
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

  <!-- Fine: required for the GPS fix used in the API call -->
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />


## iOS — ios/Runner/Info.plist

Add inside <dict>:

  <!-- Shown in the system permission dialog -->
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>Ummah uses your location to find mosques near you. Your exact coordinates are never stored.</string>

  <!-- Required if you call getCurrentPosition in the background -->
  <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
  <string>Ummah uses your location in the background to remind you of prayer times at nearby mosques.</string>


## flutter_secure_storage — Android additional config

In android/app/build.gradle, ensure:

  android {
    compileSdkVersion 34    // minimum 33
    defaultConfig {
      minSdkVersion 23      // required by flutter_secure_storage
    }
  }

In android/app/src/main/AndroidManifest.xml, inside <application>:

  <!-- Required for EncryptedSharedPreferences on Android 6+ -->
  android:allowBackup="false"
