# Prints the SHA-256 of the RELEASE keystore's signing certificate and writes
# it into expectedSigningCertSha256 (lib/core/licensing/license_keys.dart).
#
#   pwsh tool/seal_release.ps1
#
# Run it ONCE, after creating the keystore and android/key.properties
# (README.md, "The release keystore"), then commit license_keys.dart. From
# then on the app compares its own signing certificate with this value at
# every start: a copy that was modified and signed again by someone else has
# another certificate and refuses to sell.
#
# THE VALUE NEVER CHANGES AFTER THE FIRST RELEASE. It belongs to the keystore,
# and every customer's activation belongs to the keystore too (a phone's
# request code is derived from the key the app is signed with). The script
# refuses to replace a value that is already there; -Force is for the time
# BEFORE the first customer only.

[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'release_common.ps1')

$keystore = Get-ReleaseKeystore
if (-not $keystore) {
    throw 'android/key.properties was not found. Create the keystore and key.properties first (README.md, "The release keystore").'
}
$sha = Get-KeystoreSha256 $keystore

$file = 'lib/core/licensing/license_keys.dart'
$current = Get-DartConstant $file 'expectedSigningCertSha256'

Write-Host ''
Write-Host "Keystore:     $($keystore.StoreFile)"
Write-Host "Alias:        $($keystore.KeyAlias)"
Write-Host "SHA-256:      $sha"
Write-Host ''

if ($current -eq $sha) {
    Write-Host 'expectedSigningCertSha256 already holds this value. Nothing to do.' -ForegroundColor Green
    return
}
if ($current -and -not $Force) {
    throw @"
expectedSigningCertSha256 already holds ANOTHER value:
  in the app : $current
  keystore   : $sha
This keystore is not the one the app was sealed with. If licenses were issued
for builds signed with the old one, they all stop working with this one.
Use the original keystore. (Before the first release only: -Force)
"@
}

$text = Get-Content $file -Raw
$pattern = "(const\s+String\s+expectedSigningCertSha256\s*=\s*')[^']*(')"
$updated = [regex]::Replace($text, $pattern, "`${1}$sha`${2}")
if ($updated -eq $text) { throw "could not write the value into $file" }
# No BOM, and the file's own line endings.
[System.IO.File]::WriteAllText((Resolve-Path $file).Path, $updated, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Written to $file." -ForegroundColor Green
Write-Host ''
Write-Host 'Next:'
Write-Host '  1. git add lib/core/licensing/license_keys.dart ; git commit -m "Seal the release build"'
Write-Host '  2. pwsh tool/build_release.ps1'
Write-Host ''
Write-Host 'NEVER LOSE OR CHANGE: this keystore, its password, the package name' -ForegroundColor Yellow
Write-Host '(com.souqi.souqi) and licenseDeviceSalt. Every activation depends on them.' -ForegroundColor Yellow
