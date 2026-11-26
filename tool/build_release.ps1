# Builds the RELEASE APK the way it must always be built: obfuscated, with the
# debug symbols split out.
#
#   pwsh tool/build_release.ps1
#
# - "--obfuscate" renames every Dart class and function in the binary, which
#   makes the licensing code harder to find and patch.
# - "--split-debug-info" takes the symbols out of the APK. They are written to
#   symbols/<version>/ — KEEP that folder for every version you hand out: a
#   crash report from an obfuscated build can only be read with it
#   (flutter symbolize -i <stack trace> -d symbols/<version>/app.android-arm64.symbols).
#
# Do not run it while "flutter test" is running: both regenerate the l10n files.
#
# Before the first release (phase 6): fill in `expectedSigningCertSha256` and
# `licensePublicKeyHex` in lib/core/licensing/license_keys.dart, and the release
# signing config in android/app/build.gradle.kts. A release build with the
# fingerprint empty starts as "not sealed" and does not sell.

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

$versionLine = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $versionLine) { throw 'no version in pubspec.yaml' }
$version = $versionLine.Matches[0].Groups[1].Value
$symbols = "symbols/$version"

$keys = Get-Content lib/core/licensing/license_keys.dart -Raw
if ($keys -match "licensePublicKeyHex = '';") {
    Write-Warning 'licensePublicKeyHex is empty: this build cannot accept any activation code.'
}
if ($keys -match "expectedSigningCertSha256 = '';") {
    Write-Warning 'expectedSigningCertSha256 is empty: this build will report itself as "not sealed" and will not sell.'
}

flutter build apk --release --obfuscate "--split-debug-info=$symbols" @args
if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }

Write-Host ''
Write-Host "APK:      build/app/outputs/flutter-apk/app-release.apk"
Write-Host "Symbols:  $symbols   (keep this folder with the released APK)"
