# Shared by build_release.ps1 and seal_release.ps1: reading the release
# keystore and the constants in license_keys.dart. Dot-sourced, not run.

function Get-DartConstant([string]$file, [string]$name) {
    $text = Get-Content $file -Raw
    $m = [regex]::Match($text, "const\s+String\s+$name\s*=\s*'([^']*)'")
    if (-not $m.Success) { throw "$name not found in $file" }
    return $m.Groups[1].Value
}

# android/key.properties as a table, or $null when there is none.
function Get-ReleaseKeystore {
    $file = 'android/key.properties'
    if (-not (Test-Path $file)) { return $null }
    $props = @{}
    foreach ($line in Get-Content $file) {
        if ($line -match '^\s*([^#=\s][^=]*?)\s*=\s*(.*)$') {
            $props[$Matches[1]] = $Matches[2]
        }
    }
    foreach ($key in 'storeFile', 'storePassword', 'keyAlias', 'keyPassword') {
        if (-not $props[$key]) { throw "android/key.properties has no $key" }
    }
    if (-not (Test-Path $props['storeFile'])) {
        throw "The keystore of android/key.properties does not exist: $($props['storeFile'])"
    }
    $resolved = (Resolve-Path $props['storeFile']).Path
    $repo = (Resolve-Path '.').Path
    if ($resolved.StartsWith($repo, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "The keystore is INSIDE the repository ($resolved). Move it out (for example C:\SouqiKeys) and fix android/key.properties."
    }
    return [pscustomobject]@{
        StoreFile     = $resolved
        StorePassword = $props['storePassword']
        KeyAlias      = $props['keyAlias']
    }
}

# SHA-256 of the keystore's signing certificate: 64 hex characters, lower
# case, no colons - the form of expectedSigningCertSha256.
function Get-KeystoreSha256($keystore) {
    # The password goes through the environment, not the command line.
    $env:SOUQI_STOREPASS = $keystore.StorePassword
    try {
        $lines = & keytool -list -v -keystore $keystore.StoreFile -alias $keystore.KeyAlias -storepass:env SOUQI_STOREPASS 2>&1
        if ($LASTEXITCODE -ne 0) { throw "keytool failed: $($lines -join ' ')" }
    }
    finally {
        Remove-Item Env:SOUQI_STOREPASS -ErrorAction SilentlyContinue
    }
    $match = $lines | Select-String -Pattern 'SHA-?256:\s*([0-9A-Fa-f:]+)' | Select-Object -First 1
    if (-not $match) { throw 'no SHA256 line in the keytool output' }
    return ($match.Matches[0].Groups[1].Value -replace ':', '').ToLower()
}

# SHA-256 of the certificate an APK is signed with (apksigner, from the
# Android SDK build-tools), or $null when apksigner is not installed.
function Get-ApkSha256([string]$apk) {
    $sdk = $env:ANDROID_HOME
    if (-not $sdk) { $sdk = $env:ANDROID_SDK_ROOT }
    if (-not $sdk -and (Test-Path 'android/local.properties')) {
        $line = Get-Content 'android/local.properties' | Where-Object { $_ -match '^sdk\.dir=' } | Select-Object -First 1
        if ($line) { $sdk = ($line -replace '^sdk\.dir=', '') -replace '\\\\', '\' -replace '\\:', ':' }
    }
    if (-not $sdk -or -not (Test-Path "$sdk/build-tools")) { return $null }
    $tool = Get-ChildItem "$sdk/build-tools" -Directory |
        Sort-Object { [version]($_.Name -replace '[^0-9.].*$', '') } -Descending |
        ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $tool) { return $null }
    $lines = & $tool verify --print-certs $apk 2>&1
    $match = $lines | Select-String -Pattern 'certificate SHA-256 digest:\s*([0-9A-Fa-f]+)' | Select-Object -First 1
    if (-not $match) { return $null }
    return $match.Matches[0].Groups[1].Value.ToLower()
}
