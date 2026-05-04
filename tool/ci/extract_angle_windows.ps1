# Same pattern as mpv: 7z unpack for ANGLE bundle used by media_kit_libs_windows_video.
param(
    [Parameter(Mandatory = $true)][string]$Archive,
    [Parameter(Mandatory = $true)][string]$DestDir
)

$ErrorActionPreference = "Stop"
$seven = Join-Path ${env:ProgramFiles} "7-Zip\7z.exe"
if (-not (Test-Path -LiteralPath $seven)) {
    throw "7-Zip not found at $seven"
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("angle_unpack_" + [Guid]::NewGuid().ToString("n"))
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

    $egl = Join-Path $DestDir "libEGL.dll"
    if (-not (Test-Path -LiteralPath $egl)) {
        throw "libEGL.dll missing under $DestDir after extract"
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
