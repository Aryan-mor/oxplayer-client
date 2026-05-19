#Requires -Version 5.1
<#
.SYNOPSIS
    Validates the local TDLib web bundle (web/tdweb) for Mini App JSON API symbols,
    clears Flutter web build caches, and optionally re-fetches release artifacts.

.DESCRIPTION
    Use this after artifact updates or when debugging "Unknown class getMainWebApp"
    on Flutter Web. Literal searches in *.js often find nothing because TDLib
    registers types from the WASM module; this script scans all files under
    web/tdweb/ as bytes for UTF-8 substrings getMainWebApp and getWebAppUrl.

.PARAMETER FetchLatest
    Run `dart run tool/tdlib/fetch_artifacts.dart` from the oxplayer-client root
    before integrity checks (requires artifact_config.yaml and network).

.PARAMETER SkipIntegrity
    Skip the byte-level symbol scan (only cache bust / fetch / instructions).

.EXAMPLE
    .\tool\tdlib\verify_and_refresh_env.ps1

.EXAMPLE
    .\tool\tdlib\verify_and_refresh_env.ps1 -FetchLatest
#>
[CmdletBinding()]
param(
    [switch]$FetchLatest,
    [switch]$SkipIntegrity
)

# Note: Intentionally no Set-StrictMode here; some cmdlet edge cases are noisy under Latest.
$ErrorActionPreference = 'Stop'

$ClientRoot = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
$TdwebRoot = Join-Path (Join-Path $ClientRoot 'web') 'tdweb'

function Test-Utf8SubstringInFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [Parameter(Mandatory = $true)]
        [byte[]] $NeedleUtf8
    )
    if ($NeedleUtf8.Length -eq 0) { return $false }
    $len = (Get-Item -LiteralPath $Path).Length
    $maxBytes = 400MB
    if ($len -gt $maxBytes) {
        Write-Warning "Skipping oversized file for scan (${len} bytes): $Path"
        return $false
    }
    $haystack = [System.IO.File]::ReadAllBytes($Path)
    return Test-Subsequence -Haystack $haystack -Needle $NeedleUtf8
}

function Test-Subsequence {
    param([byte[]] $Haystack, [byte[]] $Needle)
    $n = $Needle.Length
    $h = $Haystack.Length
    if ($h -lt $n) { return $false }
    $limit = $h - $n
    for ($i = 0; $i -le $limit; $i++) {
        $ok = $true
        for ($j = 0; $j -lt $n; $j++) {
            if ($Haystack[$i + $j] -ne $Needle[$j]) {
                $ok = $false
                break
            }
        }
        if ($ok) { return $true }
    }
    return $false
}

function Invoke-IntegrityScan {
    param([string] $Root)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Missing directory: $Root - run fetch_artifacts or sync-tdweb before this script."
    }
    $patterns = @('getMainWebApp', 'getWebAppUrl')
    $needles = @{}
    foreach ($pat in $patterns) {
        $needles[$pat] = [System.Text.Encoding]::UTF8.GetBytes($pat)
    }
    $found = @{
        'getMainWebApp' = $false
        'getWebAppUrl'  = $false
    }

    $tdwebFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction Stop)
    if ($tdwebFiles.Length -eq 0) {
        throw "No files under $Root - bundle is empty."
    }

    foreach ($f in $tdwebFiles) {
        foreach ($pat in $patterns) {
            if ($found[$pat]) { continue }
            try {
                if (Test-Utf8SubstringInFile -Path $f.FullName -NeedleUtf8 $needles[$pat]) {
                    $found[$pat] = $true
                    $rel = $f.FullName.Substring($Root.Length).TrimStart([char[]]@('\', '/'))
                    Write-Host "[verify] Found '$pat' in $rel" -ForegroundColor Green
                }
            }
            catch {
                Write-Warning "Could not read $($f.FullName): $_"
            }
        }
    }

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($pat in $patterns) {
        if (-not $found[$pat]) {
            [void]$missing.Add($pat)
        }
    }
    if ($missing.Count -gt 0) {
        $msg = @"
[verify] FAILED: UTF-8 literals not found under web/tdweb for: $($missing -join ', ').

This usually means:
  - dist.tar.gz / tdweb layout is stale or from an older TD pin, or
  - The WASM was built without the JSON layer you expect (rare).

Next: run this script with -FetchLatest, or verify tool/tdlib/TD_VERSION.json matches
the GitHub release tag tdlib-artifacts-<commit_sha>, then re-run fetch_artifacts.dart.
"@
        throw $msg
    }
    Write-Host '[verify] Integrity OK: getMainWebApp and getWebAppUrl appear in at least one artifact under web/tdweb/.' -ForegroundColor Green
}

Write-Host "[verify] Client root: $ClientRoot" -ForegroundColor Cyan

if ($FetchLatest) {
    Write-Host '[verify] Running fetch_artifacts.dart ...' -ForegroundColor Cyan
    Push-Location $ClientRoot
    try {
        & dart run tool/tdlib/fetch_artifacts.dart
        if ($LASTEXITCODE -ne 0) {
            Write-Error "fetch_artifacts.dart exited with code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

if (-not $SkipIntegrity) {
    Invoke-IntegrityScan -Root $TdwebRoot
}
else {
    Write-Host '[verify] Skipping integrity scan (-SkipIntegrity).' -ForegroundColor Yellow
}

$cachePaths = @(
    (Join-Path (Join-Path $ClientRoot '.dart_tool') 'flutter_build'),
    (Join-Path (Join-Path $ClientRoot 'build') 'web')
)
foreach ($p in $cachePaths) {
    if (Test-Path -LiteralPath $p) {
        Write-Host "[verify] Removing cache: $p" -ForegroundColor Yellow
        Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
    }
    else {
        Write-Host "[verify] Cache path already absent: $p" -ForegroundColor DarkGray
    }
}

Write-Host @'

[verify] --- Browser cache / Service Worker (manual) ---
1. Open your Flutter web app in Chrome.
2. DevTools (F12) -> Application:
   - Service Workers -> Unregister (for this origin).
   - Storage -> Clear site data (or at least Cache storage + Local/Session storage if you use tdweb persistence).
3. Hard reload: Ctrl+Shift+R (Windows) or empty-cache reload from Network tab.
4. Re-run: flutter run -d chrome (or your pnpm flutter:web pipeline) so the
   dev server serves files from a clean build folder after cache deletion above.

[verify] Done.
'@ -ForegroundColor Cyan
