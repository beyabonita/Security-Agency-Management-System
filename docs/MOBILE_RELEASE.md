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

## Agency logo assets

The transparent agency master is
`assets/branding/twenty_twenty_security_agency_shield.png`. Keep its alpha
channel intact; the web and Guard logo containers intentionally have no tile.
To regenerate the display assets and platform launcher icons:

```powershell
dart run scripts/update_agency_branding.dart assets/branding/twenty_twenty_security_agency_shield.png
dart run flutter_launcher_icons
flutter test test/branding_transparency_test.dart
```

Android adaptive launchers use a burgundy background layer with the transparent
shield foreground. Update the release version and build number in `pubspec.yaml`
before rebuilding an APK, and keep the download page/version headers in sync.
Publish the newly verified APK together with the web changes.

The current direct-download capstone app is compiled in release mode (not
debuggable), but signed with the existing Android debug key. A compatible
capstone update must preserve release mode, that same certificate, and use a
higher build number. Do not call this signing setup production-ready:
configure a private release keystore before moving to production distribution.

If the local JBR reports `Unable to establish loopback connection` with a nested
`UnixDomainSockets.connect0` / `Invalid argument: connect`, retry with a short
existing socket directory for that command, not a firewall change:

```powershell
$releaseJavaOptions = $env:JAVA_TOOL_OPTIONS
$releaseGradleOptions = $env:GRADLE_OPTS
try {
  $env:JAVA_TOOL_OPTIONS = "$releaseJavaOptions -Djdk.net.unixdomain.tmpdir=C:\jtmp".Trim()
  $env:GRADLE_OPTS = "$releaseGradleOptions -Dorg.gradle.daemon=false".Trim()
  flutter build apk --release
} finally {
  $env:JAVA_TOOL_OPTIONS = $releaseJavaOptions
  $env:GRADLE_OPTS = $releaseGradleOptions
}
```
