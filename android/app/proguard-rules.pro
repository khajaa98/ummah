# ProGuard rules for Ummah — keep enough symbols for our plugins to work
# in --release mode.

# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**    { *; }
-keep class io.flutter.view.**    { *; }
-keep class io.flutter.**         { *; }
-keep class io.flutter.plugins.** { *; }

# flutter_local_notifications uses Gson under the hood
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.**     { *; }
-keepattributes Signature
-keepattributes *Annotation*

# flutter_secure_storage / Tink (used by EncryptedSharedPreferences)
-keep class com.google.crypto.tink.** { *; }

# RevenueCat (purchases_flutter)
-keep class com.revenuecat.purchases.** { *; }

# Sentry
-keep class io.sentry.** { *; }

# Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler   {}

# Google Play Core (Flutter references these for deferred component install,
# but we don't actually use deferred components — silence the missing-class
# warnings so R8 can finish.)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
