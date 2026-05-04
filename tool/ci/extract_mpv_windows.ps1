# Used from patched DonutWare media_kit Windows CMake (CI): reliable 7z unpack + flatten one top-level dir.
param(
    [Parameter(Mandatory = $true)][string]$Archive,
    [Parameter(Mandatory = $true)][string]$DestDir
)

$ErrorActionPreference = "Stop"
$seven = Join-Path ${env:ProgramFiles} "7-Zip\7z.exe"
if (-not (Test-Path -LiteralPath $seven)) {
    throw "7-Zip not found at $seven"
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("mpv_unpack_" + [Guid]::NewGuid().ToString("n"))
try {
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    & $seven x $Archive "-o$work" -y
    if ($LASTEXITCODE -ne 0) {
        throw "7z extract failed with exit code $LASTEXITCODE"
    }

    $dirs = @(Get-ChildItem -LiteralPath $work -Directory -ErrorAction SilentlyContinue)
    Remove-Item -LiteralPath $DestDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

    if ($dirs.Count -ge 1) {
        $inner = $dirs[0]
        Copy-Item -Path (Join-Path $inner.FullName "*") -Destination $DestDir -Recurse -Force
    }
    else {
        Copy-Item -Path (Join-Path $work "*") -Destination $DestDir -Recurse -Force
    }

    $dll = Join-Path $DestDir "libmpv-2.dll"
    if (-not (Test-Path -LiteralPath $dll)) {
        throw "libmpv-2.dll missing under $DestDir after extract"
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
