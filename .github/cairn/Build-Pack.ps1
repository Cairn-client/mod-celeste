# Copyright (C) 2026 the Cairn contributors. SPDX-License-Identifier: MIT (as the project it is part of)
<#
.SYNOPSIS
    Builds the Cairn mod pack for Celeste (CelesteNet): release\Cairn-Pack-celeste-<version>.zip and release\pack-index.json
    (what the Cairn launcher reads to see a newer pack exists).

.DESCRIPTION
    An *external* pack (docs in the launcher repository: docs/PACKS.md): CelesteNet is a mod of the Everest mod loader, which loads a mod
    from a folder of the game's Mods folder. The pack holds the client as upstream publishes it (everest.yaml and the DLLs), put in
    Mods\CelesteNet. Everest itself patches the game's executable, which a pack never does: the player installs it once.

      mod\...        the CelesteNet client, as upstream publishes it (everest.yaml, DLLs, dialog and graphics), and the licence
      pack.json      the contract with the launcher
      manifest.txt   MOD|<path>|<size>|<sha256>, one line per file

    The pack's version is the VERSION file (strict X.Y.Z, this project's own); the version of CelesteNet it carries is the pack's "upstream"
    (UPSTREAM.md, "upstream-release:").
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $SourceDir,       # the unpacked upstream release
    [Parameter(Mandatory)][string] $UpstreamVersion  # the upstream release it came from
)

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$version = (Get-Content (Join-Path $root 'VERSION') -TotalCount 1).Trim()
if ($version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw "VERSION must be strict X.Y.Z, got '$version'" }
if ($UpstreamVersion -cnotmatch '^[0-9A-Za-z.+-]+$') { throw "upstream version looks wrong: '$UpstreamVersion'" }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$release = Join-Path $root 'release'
$stage = Join-Path $release 'pack-stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$mod = Join-Path $stage 'mod'
New-Item -ItemType Directory -Force -Path $mod | Out-Null

foreach ( in 'everest.yaml', 'CelesteNet.Client.dll') {
    if (-not (Test-Path (Join-Path $SourceDir $need))) { throw "the upstream release has no $need" }
}
Copy-Item (Join-Path $SourceDir '*') $mod -Recurse
Copy-Item (Join-Path $root 'LICENSE') (Join-Path $mod 'LICENSE')

function Get-Sha256([string] $Path) { (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

$launcherMin = '0.3.23'
$packJson = [ordered]@{
    schema      = 2
    id          = 'celeste'
    game        = 'celeste'
    version     = $version
    upstream    = $UpstreamVersion
    kind        = 'external'
    installDir  = 'Mods/CelesteNet'
    launcherMin = $launcherMin
}
[IO.File]::WriteAllText((Join-Path $stage 'pack.json'), (($packJson | ConvertTo-Json) + "`n"), (New-Object System.Text.UTF8Encoding($false)))

$lines = New-Object System.Collections.Generic.List[string]
foreach ($f in Get-ChildItem $mod -Recurse -File | Sort-Object FullName) {
    $rel = $f.FullName.Substring($mod.Length + 1)
    $lines.Add(('MOD|{0}|{1}|{2}' -f $rel, $f.Length, (Get-Sha256 $f.FullName)))
}
[IO.File]::WriteAllText((Join-Path $stage 'manifest.txt'), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))

$zipName = "Cairn-Pack-celeste-$version.zip"
$zipPath = Join-Path $release $zipName
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
$fs = [IO.File]::Open($zipPath, 'Create')
try {
    $z = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in Get-ChildItem $stage -Recurse -File) {
            $rel = $f.FullName.Substring($stage.Length + 1) -replace '\\', '/'
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, $f.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $z.Dispose() }
} finally { $fs.Dispose() }

$index = [ordered]@{
    schema      = 2
    id          = 'celeste'
    game        = 'celeste'
    version     = $version
    upstream    = $UpstreamVersion
    kind        = 'external'
    file        = $zipName
    sha256      = Get-Sha256 $zipPath
    size        = (Get-Item $zipPath).Length
    launcherMin = $launcherMin
}
[IO.File]::WriteAllText((Join-Path $release 'pack-index.json'), (($index | ConvertTo-Json) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "pack: $zipPath ($([math]::Round((Get-Item $zipPath).Length / 1MB, 1)) MB), version $version, CelesteNet $UpstreamVersion, $($lines.Count) files"
