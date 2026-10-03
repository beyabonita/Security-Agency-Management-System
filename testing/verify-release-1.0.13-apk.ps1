$ErrorActionPreference = 'Stop'
$releaseApk = Join-Path (Get-Location) 'build/app/outputs/flutter-apk/app-release.apk'
$oldReleaseApk = Join-Path (Get-Location) 'web/downloads/security-agency-management-system-guard.apk'
$androidBuildTools = Join-Path $env:LOCALAPPDATA 'Android/Sdk/build-tools/36.1.0'
$releaseSignature = & (Join-Path $androidBuildTools 'apksigner.bat') verify --print-certs $releaseApk 2>&1
if ($LASTEXITCODE -ne 0) { throw 'New APK signature verification failed.' }
$oldSignature = & (Join-Path $androidBuildTools 'apksigner.bat') verify --print-certs $oldReleaseApk 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Previous APK signature verification failed.' }
$signaturePattern = 'Signer #1 certificate SHA-256 digest: ([a-f0-9]+)'
$newCertificate = [regex]::Match(($releaseSignature -join "`n"),$signaturePattern).Groups[1].Value
$oldCertificate = [regex]::Match(($oldSignature -join "`n"),$signaturePattern).Groups[1].Value
if (!$newCertificate -or $newCertificate -ne $oldCertificate) { throw 'Signing certificate differs; existing installations cannot be updated safely.' }
$apkMetadata = & (Join-Path $androidBuildTools 'aapt.exe') dump badging $releaseApk 2>&1
if ($LASTEXITCODE -ne 0) { throw 'APK metadata verification failed.' }
$metadataText = $apkMetadata -join "`n"
if ($metadataText -notmatch "package: name='com.sentinellink.app' versionCode='14' versionName='1.0.13'") { throw 'Wrong app identifier or release version.' }
if ($metadataText -match 'application-debuggable') { throw 'APK is debuggable.' }
$releaseManifest = & (Join-Path $androidBuildTools 'aapt.exe') dump xmltree $releaseApk AndroidManifest.xml 2>&1
if ($LASTEXITCODE -ne 0) { throw 'APK manifest inspection failed.' }
if (($releaseManifest -join "`n") -match 'android:debuggable[^\r\n]*0xffffffff') { throw 'APK manifest enables debugging.' }
$releaseVerification = [pscustomobject]@{
  version='1.0.13'; build=14; applicationId='com.sentinellink.app';
  releaseMode=$true; sameSigningCertificate=$true; certificateSha256=$newCertificate;
  sha256=(Get-FileHash -LiteralPath $releaseApk -Algorithm SHA256).Hash.ToLowerInvariant();
  bytes=(Get-Item -LiteralPath $releaseApk).Length
}
$releaseVerification | ConvertTo-Json | Set-Content -LiteralPath testing/release-1.0.13-apk-verification.json -Encoding utf8
$releaseSignature | Set-Content -LiteralPath testing/release-1.0.13-apk-signature.txt -Encoding utf8
$apkMetadata | Set-Content -LiteralPath testing/release-1.0.13-apk-metadata.txt -Encoding utf8
Copy-Item -LiteralPath $releaseApk -Destination $oldReleaseApk -Force
$releaseVerification | ConvertTo-Json
