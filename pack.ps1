#requires -Version 5.1
<#
.SYNOPSIS
    Packs regions/ into the assets of one release: per region a mesh zip, an overlays zip, their .sha256 files, and
    supplements.json, the list OrthoStreamXP reads.

.PARAMETER Tag
    The release's tag (v1, v2, ...): the files' download addresses point at it.

.PARAMETER Previous
    supplements.json of the release before, when there is one. A region whose files changed must raise its version
    (regions/<id>/region.json), or installed copies would never get the change: that stops the pack.

.EXAMPLE
    ./pack.ps1 -Tag v2 -Previous prev/supplements.json

.NOTES
    Runs on Windows PowerShell 5.1 and PowerShell 7 (Windows or Linux).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidatePattern('^v\d+(\.\d+)*$')] [string] $Tag,
    [string] $Out = (Join-Path $PSScriptRoot 'out'),
    [string] $Previous,
    [string] $Repository = 'flysimdev/orthostreamxp-scenery'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

& (Join-Path $PSScriptRoot 'check.ps1')
if ($LASTEXITCODE -ne 0) { throw 'regions/ has errors (above): nothing was packed' }

$root = Join-Path $PSScriptRoot 'regions'
$Out = [IO.Path]::GetFullPath($Out)
$download = "https://github.com/$Repository/releases/download/$Tag"
# A fixed time for every entry: the same files make the same zip.
$entryTime = [DateTimeOffset]::new(2020, 1, 1, 0, 0, 0, [TimeSpan]::Zero)

function Get-Sha256([string] $path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }

# The files under a folder, relative with forward slashes, in a fixed (ordinal) order.
function Get-Files([string] $folder) {
    if (-not (Test-Path -LiteralPath $folder)) { return @() }
    $prefix = [IO.Path]::GetFullPath($folder).TrimEnd('\', '/')
    $files = @(Get-ChildItem -LiteralPath $folder -Recurse -File | ForEach-Object {
        [pscustomobject]@{ Path = $_.FullName; Relative = $_.FullName.Substring($prefix.Length + 1).Replace('\', '/') }
    })
    if ($files.Count -gt 1) { [Array]::Sort([string[]]($files | ForEach-Object Relative), $files, [StringComparer]::Ordinal) }
    return $files
}

# A zip whose one top folder is <top>/, as AutoOrtho's are (OrthoStreamXP takes the folder off as it unpacks).
function New-Zip([string] $folder, [string] $top, [string] $zipPath) {
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath }
    $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in Get-Files $folder) {
            $entry = $zip.CreateEntry("$top/$($file.Relative)", [IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $entryTime # before the entry is written: it cannot change after
            $target = $entry.Open()
            $source = [IO.File]::OpenRead($file.Path)
            try { $source.CopyTo($target) } finally { $source.Dispose(); $target.Dispose() }
        }
    } finally { $zip.Dispose() }
}

# The asset as supplements.json lists it, with its .sha256 beside it ("<hash>  <name>", as sha256sum writes).
function New-Asset([string] $zipPath) {
    $name = Split-Path $zipPath -Leaf
    $hash = Get-Sha256 $zipPath
    [IO.File]::WriteAllText("$zipPath.sha256", "$hash  $name", [Text.Encoding]::ASCII)
    [ordered]@{ name = $name; url = "$download/$name"; size = (Get-Item -LiteralPath $zipPath).Length; sha256Url = "$download/$name.sha256" }
}

# One hash of all a region's files (names and contents): tells whether they changed since the release before.
function Get-ContentHash([string] $regionFolder) {
    $lines = foreach ($part in 'mesh', 'overlays') {
        foreach ($file in Get-Files (Join-Path $regionFolder $part)) { "$part/$($file.Relative):$(Get-Sha256 $file.Path)" }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))) } finally { $sha.Dispose() }
    return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
}

# The regions of the release before, by id.
$before = @{}
if ($Previous -and (Test-Path -LiteralPath $Previous)) {
    $previousRegions = (Get-Content -LiteralPath $Previous -Raw | ConvertFrom-Json).regions
    foreach ($property in $previousRegions.PSObject.Properties) { $before[$property.Name] = $property.Value }
}
if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse }
New-Item -ItemType Directory -Path $Out | Out-Null

$manifest = [ordered]@{ schema = 1; tag = $Tag; regions = [ordered]@{} }
foreach ($region in Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name) {
    $id = $region.Name
    $version = [int](Get-Content -LiteralPath (Join-Path $region.FullName 'region.json') -Raw | ConvertFrom-Json).version
    $contentHash = Get-ContentHash $region.FullName
    if ($before.ContainsKey($id)) {
        $old = $before[$id]
        if ($old.contentHash -ne $contentHash -and $version -le [int]$old.version) {
            throw "regions/$id changed since the release before, but its version is still ${version}: raise it in regions/$id/region.json"
        }
        if ($old.contentHash -eq $contentHash -and $version -ne [int]$old.version) {
            Write-Warning "regions/$id did not change, but its version went from $($old.version) to ${version}: every installed copy downloads it again"
        }
    }

    [string[]] $tiles = @(Get-ChildItem -LiteralPath (Join-Path $region.FullName 'mesh/Earth nav data') -Recurse -File -Filter '*.dsf' |
        ForEach-Object BaseName | Sort-Object)
    $entry = [ordered]@{ version = $version; tiles = $tiles; contentHash = $contentHash }

    $meshZip = Join-Path $Out "z_${id}_supplement.zip"
    New-Zip (Join-Path $region.FullName 'mesh') "z_${id}_supplement" $meshZip
    $entry.mesh = New-Asset $meshZip
    $summary = '{0}: version {1}, {2} tiles, mesh {3:N1} MB' -f $id, $version, $tiles.Count, ($entry.mesh.size / 1MB)
    $overlays = Join-Path $region.FullName 'overlays'
    if (Test-Path -LiteralPath $overlays) {
        $overlayZip = Join-Path $Out "y_${id}_supplement_overlays.zip"
        New-Zip $overlays "y_${id}_supplement_overlays" $overlayZip
        $entry.overlays = New-Asset $overlayZip
        $summary += ', overlays {0:N1} MB' -f ($entry.overlays.size / 1MB)
    }
    $manifest.regions[$id] = $entry
    Write-Host $summary
}

$json = $manifest | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText((Join-Path $Out 'supplements.json'), $json, [Text.UTF8Encoding]::new($false))
Write-Host "Packed into $Out for $Tag"
