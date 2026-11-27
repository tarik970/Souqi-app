# Builds the RELEASE APK the way it must always be built, and puts everything
# that belongs to that version into ONE folder you can archive:
#
#   pwsh tool/build_release.ps1
#
#   releases/<version>/
#     souqi-<version>.apk     the APK to hand out (arm + arm64, every real phone)
#     symbols/                Dart debug symbols (--split-debug-info)
#     mapping.txt             R8's name map of the Android side
#     build-info.txt          date, git commit, Flutter version, certificate, sizes
#
# KEEP THAT FOLDER FOR EVERY VERSION YOU HAND OUT. The stack traces in a
# customer's error log (Settings -> About -> Share error log) are obfuscated;
# they can only be read with the symbols of the SAME build:
#
#   flutter symbolize -i souqi-error-log.txt -d releases/<version>/symbols/app.android-arm64.symbols
#
# What it does:
# - refuses to build unless android/key.properties points at the release
#   keystore AND that keystore's certificate is the one in
#   expectedSigningCertSha256 (lib/core/licensing/license_keys.dart) — an APK
#   signed with any other key shows a different request code on every phone
#   and refuses to sell;
# - "--obfuscate" renames every Dart class and function in the binary, which
#   makes the licensing code harder to find and patch;
# - "--split-debug-info" takes the symbols out of the APK into the folder
#   above;
# - fails if a libapp.so in the built APK still has .debug_* (DWARF) sections;
# - checks the certificate of the APK it built.
#
# -AllowDebugSigning   builds without the release key (signed with the debug
#                      key) to look at the size or try the build on your own
#                      phone. Such an APK NEVER goes to a customer: it reports
#                      itself as modified and does not sell. Its folder is
#                      releases/<version>-UNSIGNED/.
#
# Do not run it while "flutter test" is running: both regenerate the l10n
# files. Extra arguments are passed on to "flutter build apk".

[CmdletBinding()]
param(
    [switch]$AllowDebugSigning,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArgs
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
. (Join-Path $PSScriptRoot 'release_common.ps1')

# ---- The version ---------------------------------------------------------
$versionLine = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $versionLine) { throw 'no version in pubspec.yaml' }
$version = $versionLine.Matches[0].Groups[1].Value

# ---- The keys ------------------------------------------------------------
$keysFile = 'lib/core/licensing/license_keys.dart'
$publicKey = Get-DartConstant $keysFile 'licensePublicKeyHex'
$expected = Get-DartConstant $keysFile 'expectedSigningCertSha256'
if (-not $publicKey) {
    throw 'licensePublicKeyHex is empty: this build could not accept any activation code.'
}

$keystore = Get-ReleaseKeystore
if ($keystore) {
    $actual = Get-KeystoreSha256 $keystore
    if (-not $expected) {
        throw "expectedSigningCertSha256 is empty. Run:  pwsh tool/seal_release.ps1"
    }
    if ($actual -ne $expected) {
        throw @"
The release keystore does not match expectedSigningCertSha256.
  keystore : $actual
  expected : $expected
An APK signed with this keystore would refuse to sell on every phone.
Use the ORIGINAL keystore. (Only before the very first release: pwsh tool/seal_release.ps1 -Force)
"@
    }
    $out = "releases/$version"
    Write-Host "Release key: $($keystore.StoreFile)  (certificate matches)" -ForegroundColor Green
}
elseif ($AllowDebugSigning) {
    $out = "releases/$version-UNSIGNED"
    Write-Warning 'NO RELEASE KEY: this APK is signed with the DEBUG key. It reports itself as modified and does not sell. NEVER hand it to a customer.'
}
else {
    throw @'
android/key.properties was not found: there is no release key to sign with.
Create the keystore and key.properties first (README.md, "The release keystore"),
then:  pwsh tool/seal_release.ps1
(To build without it, only to look at the size:  pwsh tool/build_release.ps1 -AllowDebugSigning)
'@
}

if (Get-Process -Name flutter_tester -ErrorAction SilentlyContinue) {
    throw '"flutter test" is running. Wait for it: both regenerate the l10n files.'
}

# ---- The build -----------------------------------------------------------
$symbols = "$out/symbols"
New-Item -ItemType Directory -Force $symbols | Out-Null

# arm + arm64 = every real phone. x86_64 (emulators) is left out: it would
# add a third copy of the engine and of the app to the APK. ONE universal
# APK on purpose, never "--split-per-abi": split APKs get different version
# codes, and a phone that has one of them cannot be updated with the other.
$buildArgs = @(
    'build', 'apk', '--release',
    '--obfuscate', "--split-debug-info=$symbols",
    '--target-platform', 'android-arm,android-arm64'
) + $FlutterArgs
& flutter @buildArgs
if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }

$built = 'build/app/outputs/flutter-apk/app-release.apk'
if (-not (Test-Path $built)) { throw "no APK at $built" }

# The "unobfuscated DWARF debugging information, use --strip" warning above is
# about gen_snapshot's own file, which the Android build strips. Checked here,
# before the APK goes into the release folder.
$strippedLibs = Assert-ApkLibappStripped $built
Write-Host "No DWARF debug info in: $($strippedLibs -join ', ')" -ForegroundColor Green

$apk = "$out/souqi-$version.apk"
Copy-Item $built $apk -Force

$mapping = 'build/app/outputs/mapping/release/mapping.txt'
if (Test-Path $mapping) { Copy-Item $mapping "$out/mapping.txt" -Force }
else { Write-Warning "no R8 mapping at $mapping" }

# ---- Check what was built --------------------------------------------------
$apkCert = Get-ApkSha256 $apk
if ($keystore) {
    if (-not $apkCert) {
        Write-Warning 'apksigner was not found (Android SDK build-tools): the APK certificate was not checked.'
    }
    elseif ($apkCert -ne $expected) {
        throw "The built APK is signed with $apkCert, not with the release key. Do not hand it out."
    }
}

$size = (Get-Item $apk).Length
$sha = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower()
$commit = (& git rev-parse --short HEAD 2>$null)
$dirty = if (& git status --porcelain 2>$null) { ' (with uncommitted changes)' } else { '' }
$flutterVersion = (& flutter --version 2>$null | Select-Object -First 1)
$signedWith = if ($keystore) { 'the release key' } else { 'the DEBUG key - NOT FOR CUSTOMERS' }
@"
Souqi $version
Built:        $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
Git commit:   $commit$dirty
Flutter:      $flutterVersion
Signed with:  $signedWith
Certificate:  $apkCert
APK:          souqi-$version.apk
APK size:     $size bytes ($([math]::Round($size / 1MB, 1)) MB)
APK SHA-256:  $sha
ABIs:         armeabi-v7a, arm64-v8a

To read an obfuscated stack trace from this build:
  flutter symbolize -i <error log> -d symbols/app.android-arm64.symbols
  (app.android-arm.symbols for a 32-bit phone)
"@ | Set-Content -Encoding utf8 "$out/build-info.txt"

Write-Host ''
Write-Host "APK:      $apk   ($([math]::Round($size / 1MB, 1)) MB)"
Write-Host "Symbols:  $symbols"
Write-Host "Folder:   $out   <- archive this whole folder with the release"
if (-not $keystore) {
    Write-Warning 'Signed with the DEBUG key: not for customers.'
}
