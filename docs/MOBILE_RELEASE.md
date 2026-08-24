# Sentinel Link Android release

The Android application ID is `com.sentinellink.app`. Confirm that identifier
before the first Play Store upload: it cannot be changed for an existing
published application.

## One-time signing setup

1. Create the ignored key directory:

   ```powershell
   New-Item -ItemType Directory -Force android/keys
   ```

2. Create a private keystore. Let `keytool` prompt for the passwords rather
   than putting them into your shell history:

   ```powershell
   keytool -genkeypair -v -keystore android/keys/sentinel-link-release.jks -alias sentinel-link -keyalg RSA -keysize 2048 -validity 10000
   ```

3. Copy `android/signing.properties.example` to
   `android/signing.properties`, then replace its two password placeholders.
   This local file and the keystore are ignored by Git.

## Build and verify

```powershell
flutter test
flutter analyze --no-fatal-infos
flutter build appbundle --release
```

Use the generated `build/app/outputs/bundle/release/app-release.aab` for
Google Play. For a direct install or device test, build an APK instead:

```powershell
flutter build apk --release
```

The release task intentionally stops with a clear error until signing is
configured; it will not silently produce a debug-signed production package.
