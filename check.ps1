#requires -Version 5.1
<#
.SYNOPSIS
    Checks the regions/ tree before it is packed: what OrthoStreamXP expects of a supplement.

.DESCRIPTION
    regions/<id>/region.json      { "version": N }, N >= 1 (raise it whenever the region's files change)
    regions/<id>/mesh/Earth nav data/<+40-130>/<+44-122>.dsf
    regions/<id>/mesh/textures/*.png                (the tiles' sea masks)
    regions/<id>/overlays/Earth nav data/<+40-130>/<+44-122>.dsf

    <id> is one of AutoOrtho's regions. Every tile has a mesh DSF and an overlay DSF, in the 10-degree folder it
    belongs to, and appears in one region only. DSFs are plain (XPLNEDSF), not 7-Zip compressed, as AutoOrtho's are:
    OrthoStreamXP reads their roads for the night lights and their terrain list for the load-ahead. No file reaches
    GitHub's 100 MB limit. Exits 1 on any error.

    Runs on Windows PowerShell 5.1 and PowerShell 7 (Windows or Linux).
#>
[CmdletBinding()]
param([string] $Root = (Join-Path $PSScriptRoot 'regions'))

$ErrorActionPreference = 'Stop'
$known = 'eur', 'na', 'sa', 'afr', 'asi', 'aus_pac'
$errors = [System.Collections.Generic.List[string]]::new()
$seen = @{}   # tile -> region

function Fail([string] $message) { $errors.Add($message) }

# A path under $base, relative with forward slashes (both are full paths, as Get-ChildItem gives them).
function Get-Relative([string] $base, [string] $path) {
    $prefix = [IO.Path]::GetFullPath($base).TrimEnd('\', '/')
    return [IO.Path]::GetFullPath($path).Substring($prefix.Length + 1).Replace('\', '/')
}

function Get-Sign([double] $value) { if ($value -lt 0) { '-' } else { '+' } }

# What a DSF file is: 'plain' (XPLNEDSF), '7zip' (compressed) or 'other'.
function Get-DsfKind([string] $path) {
    $bytes = [byte[]]::new(8)
    $stream = [IO.File]::OpenRead($path)
    try { $read = $stream.Read($bytes, 0, 8) } finally { $stream.Dispose() }
    if ($read -eq 8 -and [Text.Encoding]::ASCII.GetString($bytes) -eq 'XPLNEDSF') { return 'plain' }
    $sevenZip = $read -ge 6 -and $bytes[0] -eq 0x37 -and $bytes[1] -eq 0x7A -and $bytes[2] -eq 0xBC -and $bytes[3] -eq 0xAF -and $bytes[4] -eq 0x27 -and $bytes[5] -eq 0x1C
    if ($sevenZip) { return '7zip' }
    return 'other'
}

# The 10-degree folder of a tile: +44-122 is in +40-130 (rounded down, south and west included).
function Get-TileFolder([string] $tile) {
    $lat = [int]$tile.Substring(0, 3); $lon = [int]$tile.Substring(3, 4)
    $flat = [Math]::Floor($lat / 10) * 10; $flon = [Math]::Floor($lon / 10) * 10
    return ('{0}{1:00}{2}{3:000}' -f (Get-Sign $flat), [Math]::Abs($flat), (Get-Sign $flon), [Math]::Abs($flon))
}

# The tiles of one Earth nav data folder, checking each DSF on the way.
function Get-Tiles([string] $earthNavData, [string] $label) {
    $tiles = @{}
    if (-not (Test-Path -LiteralPath $earthNavData -PathType Container)) { Fail "$label has no 'Earth nav data' folder"; return $tiles }
    foreach ($file in Get-ChildItem -LiteralPath $earthNavData -Recurse -File) {
        $relative = Get-Relative $earthNavData $file.FullName
        $parts = $relative.Split('/')
        if ($parts.Count -ne 2 -or $file.Extension -ne '.dsf' -or $file.BaseName -notmatch '^[+-]\d{2}[+-]\d{3}$') {
            Fail "$label/Earth nav data/$relative is not a tile DSF (<+40-130>/<+44-122>.dsf)"; continue
        }
        if ($parts[0] -ne (Get-TileFolder $file.BaseName)) { Fail "$label/Earth nav data/$relative belongs in $(Get-TileFolder $file.BaseName)/" }
        switch (Get-DsfKind $file.FullName) {
            # OrthoStreamXP reads the roads (night lights) and the terrain list (load-ahead) of plain DSFs only, and
            # AutoOrtho's are plain: a compressed tile would have no night lights and no textures prepared ahead.
            '7zip' { Fail "$label/Earth nav data/$relative is 7-Zip compressed: unpack it (7z e <file>), OrthoStreamXP reads only plain DSFs" }
            'other' { Fail "$label/Earth nav data/$relative is not a DSF (no XPLNEDSF header)" }
        }
        $tiles[$file.BaseName] = $true
    }
    return $tiles
}

if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "No regions folder at $Root" }
$regions = Get-ChildItem -LiteralPath $Root -Directory
if ($regions.Count -eq 0) { Fail 'regions/ holds no region' }

foreach ($region in $regions) {
    $id = $region.Name
    $label = "regions/$id"
    if ($id -cnotin $known) { Fail "$label is not one of AutoOrtho's regions ($($known -join ', '))"; continue }

    $info = Join-Path $region.FullName 'region.json'
    if (-not (Test-Path -LiteralPath $info)) { Fail "$label has no region.json" }
    else {
        try { $version = (Get-Content -LiteralPath $info -Raw | ConvertFrom-Json).version } catch { $version = $null }
        if ($version -isnot [long] -and $version -isnot [int] -or $version -lt 1) { Fail "$label/region.json needs a whole ""version"" of 1 or more" }
    }

    foreach ($entry in Get-ChildItem -LiteralPath $region.FullName) {
        if ($entry.Name -notin 'region.json', 'mesh', 'overlays') { Fail "$label/$($entry.Name) is not expected (only region.json, mesh/, overlays/)" }
    }

    $mesh = Join-Path $region.FullName 'mesh'
    foreach ($entry in Get-ChildItem -LiteralPath $mesh -ErrorAction SilentlyContinue) {
        if ($entry.Name -notin 'Earth nav data', 'textures') { Fail "$label/mesh/$($entry.Name) is not expected (only Earth nav data/, textures/; .ter files are made by OrthoStreamXP)" }
    }
    foreach ($png in Get-ChildItem -LiteralPath (Join-Path $mesh 'textures') -Recurse -File -ErrorAction SilentlyContinue) {
        $relative = Get-Relative (Join-Path $mesh 'textures') $png.FullName
        if ($png.Extension -ne '.png' -or $relative.Contains('/')) { Fail "$label/mesh/textures/$relative is not expected (only *.png at the top of textures/)" }
    }

    $meshTiles = Get-Tiles (Join-Path $mesh 'Earth nav data') "$label/mesh"
    $overlayRoot = Join-Path $region.FullName 'overlays'
    $overlayTiles = if (Test-Path -LiteralPath $overlayRoot) { Get-Tiles (Join-Path $overlayRoot 'Earth nav data') "$label/overlays" } else { @{} }
    if ($meshTiles.Count -eq 0) { Fail "$label/mesh has no tile" }
    foreach ($tile in $meshTiles.Keys) { if (-not $overlayTiles.ContainsKey($tile)) { Fail "${label}: $tile has a mesh DSF but no overlay DSF" } }
    foreach ($tile in $overlayTiles.Keys) { if (-not $meshTiles.ContainsKey($tile)) { Fail "${label}: $tile has an overlay DSF but no mesh DSF" } }
    foreach ($tile in $meshTiles.Keys) {
        if ($seen.ContainsKey($tile)) { Fail "$tile is in both regions/$($seen[$tile]) and $label" } else { $seen[$tile] = $id }
    }

    foreach ($file in Get-ChildItem -LiteralPath $region.FullName -Recurse -File) {
        $mb = $file.Length / 1MB
        if ($mb -ge 100) { Fail "$(Get-Relative $Root $file.FullName) is $([Math]::Round($mb)) MB: GitHub refuses files of 100 MB or more" }
        elseif ($mb -ge 50) { Write-Warning "$(Get-Relative $Root $file.FullName) is $([Math]::Round($mb)) MB: GitHub warns above 50 MB" }
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "error: $_" -ForegroundColor Red }
    Write-Host "$($errors.Count) error(s)" -ForegroundColor Red
    exit 1
}
Write-Host "regions/ is fine: $($seen.Count) tiles in $($regions.Count) region(s)"
exit 0
