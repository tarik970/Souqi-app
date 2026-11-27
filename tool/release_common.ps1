# Shared by build_release.ps1 and seal_release.ps1: reading the release
# keystore and the constants in license_keys.dart, and checking the built
# APK. Dot-sourced, not run.

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

# The sections of an ELF file (.so) whose name starts with ".debug" - DWARF
# debugging information - as "name (size bytes)" strings; empty when there
# are none. Reads the section header table itself: Windows has no readelf.
function Get-ElfDebugSections([byte[]]$b) {
    if ($b.Length -lt 52 -or $b[0] -ne 0x7f -or $b[1] -ne 0x45 -or $b[2] -ne 0x4c -or $b[3] -ne 0x46) {
        throw 'not an ELF file'
    }
    if ($b[5] -ne 1) { throw 'not a little-endian ELF file' }
    $is64 = $b[4] -eq 2
    if ($is64) {
        $shoff = [long][BitConverter]::ToUInt64($b, 0x28)
        $entsize = [long][BitConverter]::ToUInt16($b, 0x3a)
        $count = [long][BitConverter]::ToUInt16($b, 0x3c)
        $strndx = [long][BitConverter]::ToUInt16($b, 0x3e)
    }
    else {
        $shoff = [long][BitConverter]::ToUInt32($b, 0x20)
        $entsize = [long][BitConverter]::ToUInt16($b, 0x2e)
        $count = [long][BitConverter]::ToUInt16($b, 0x30)
        $strndx = [long][BitConverter]::ToUInt16($b, 0x32)
    }
    if ($count -eq 0) { return @() }
    if ($strndx -ge $count -or $shoff + $count * $entsize -gt $b.Length) { throw 'broken ELF section table' }

    # name = offset into the section-name table; then file offset and size.
    $section = {
        param([long]$i)
        $o = $shoff + $i * $entsize
        if ($is64) {
            [pscustomobject]@{ Name = [long][BitConverter]::ToUInt32($b, $o); Offset = [long][BitConverter]::ToUInt64($b, $o + 0x18); Size = [long][BitConverter]::ToUInt64($b, $o + 0x20) }
        }
        else {
            [pscustomobject]@{ Name = [long][BitConverter]::ToUInt32($b, $o); Offset = [long][BitConverter]::ToUInt32($b, $o + 0x10); Size = [long][BitConverter]::ToUInt32($b, $o + 0x14) }
        }
    }
    $names = & $section $strndx
    $found = @()
    for ($i = 0; $i -lt $count; $i++) {
        $s = & $section $i
        $start = $names.Offset + $s.Name
        $end = $start
        while ($end -lt $b.Length -and $b[$end] -ne 0) { $end++ }
        $name = [System.Text.Encoding]::ASCII.GetString($b, $start, $end - $start)
        if ($name.StartsWith('.debug')) { $found += "$name ($($s.Size) bytes)" }
    }
    return $found
}

# Throws when any lib/<abi>/libapp.so inside the APK still carries DWARF
# debugging information; returns the libapp.so entries it checked.
#
# gen_snapshot prints "The generated ELF library contains unobfuscated DWARF
# debugging information ... use --strip" on EVERY obfuscated build. That is
# about its own output (~4 MB of .debug_info/.debug_line per ABI); the
# Android build's stripReleaseDebugSymbols task strips it before packaging.
# This checks what was packaged instead of trusting the warning: if a
# toolchain change ever stops that strip, the APK would carry the real Dart
# names --obfuscate hides (the licensing code included) and the debug info
# --split-debug-info is meant to keep out of it.
function Assert-ApkLibappStripped([string]$apk) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $apk).Path)
    try {
        $libs = @($zip.Entries | Where-Object { $_.FullName -like 'lib/*/libapp.so' })
        if (-not $libs) { throw "no lib/*/libapp.so in $apk" }
        $bad = @()
        foreach ($entry in $libs) {
            $buffer = [System.IO.MemoryStream]::new()
            $stream = $entry.Open()
            try { $stream.CopyTo($buffer) } finally { $stream.Dispose() }
            $debug = Get-ElfDebugSections $buffer.ToArray()
            if ($debug) { $bad += "  $($entry.FullName): $($debug -join ', ')" }
        }
        if ($bad) {
            throw @"
The APK still contains DWARF debugging information (unobfuscated names):
$($bad -join "`n")
The Android build did not strip libapp.so. Do not hand this APK out.
"@
        }
        return $libs.FullName
    }
    finally {
        $zip.Dispose()
    }
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
