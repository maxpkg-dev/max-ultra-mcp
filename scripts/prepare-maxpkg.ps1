# Prepares reproducible project-local settings for the pinned MaxPkg Packager.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

[CmdletBinding()]
param(
    [switch]$SkipToolSync
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fileManifestPath = Join-Path $projectRoot 'maxpkg-files.txt'
$versionIniPath = Join-Path $projectRoot 'version.ini'
$packageJsonPath = Join-Path $projectRoot 'core\package.json'
$trackedChangelogPath = Join-Path $projectRoot 'CHANGELOG.md'
$packagerIconPath = Join-Path $projectRoot 'maxpkg-icon.svg'
$settingsPath = Join-Path $projectRoot 'maxpkg-packager.ini'
$changelogPath = Join-Path $projectRoot 'maxpkg-changelog.ini'
$outputFolder = Join-Path $projectRoot 'dist\maxpkg'
$packageGuid = 'c6977570-25a6-41b0-b9bb-b3be8101123c'

. (Join-Path $PSScriptRoot 'release-mzp-utils.ps1')

if (-not $SkipToolSync) {
    & (Join-Path $PSScriptRoot 'sync-maxpkg-tooling.ps1')
}
foreach ($requiredTool in @('maxpkg-packager.ms','_install.ms','_uninstall.ms')) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $requiredTool) -PathType Leaf)) {
        throw "$requiredTool is missing. Run scripts\sync-maxpkg-tooling.ps1 first."
    }
}
if (-not (Test-Path -LiteralPath $fileManifestPath -PathType Leaf)) { throw 'maxpkg-files.txt is missing.' }
if (-not (Test-Path -LiteralPath $packagerIconPath -PathType Leaf)) { throw 'The source-controlled maxpkg-icon.svg file is missing.' }
if (-not (Test-Path -LiteralPath $trackedChangelogPath -PathType Leaf)) { throw 'CHANGELOG.md is missing.' }

$projectVersion = Get-MaxUltraProjectVersionInfo -VersionIniPath $versionIniPath
$packageData = Get-Content -LiteralPath $packageJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$version = $projectVersion.Version
if ([string]$packageData.version -ne $version) {
    throw 'core\package.json does not match version.ini. Run scripts\prepare-release.ps1.'
}
$changelogContent = [IO.File]::ReadAllText($trackedChangelogPath)
$releaseSection = [regex]::Match(
    $changelogContent,
    "(?ms)^## $([regex]::Escape($version)) - (?<date>[0-9]{4}-[0-9]{2}-[0-9]{2})\s*\r?\n(?<body>.*?)(?=^## |\z)"
)
if (-not $releaseSection.Success) {
    throw "CHANGELOG.md does not contain a dated $version release section."
}
$releaseDate = $releaseSection.Groups['date'].Value
$changelogEntries = New-Object System.Collections.Generic.List[object]
foreach ($releaseLine in $releaseSection.Groups['body'].Value -split '\r?\n') {
    if ([string]::IsNullOrWhiteSpace($releaseLine)) { continue }
    $entryMatch = [regex]::Match($releaseLine, '^- (?<type>Added|Changed|Improved|Fixed|Removed): (?<message>.+)$')
    if (-not $entryMatch.Success) { throw "Unsupported $version changelog entry: $releaseLine" }
    $changelogEntries.Add([pscustomobject]@{
        Type = $entryMatch.Groups['type'].Value
        Message = $entryMatch.Groups['message'].Value.Trim()
    })
}
if ($changelogEntries.Count -eq 0) { throw "CHANGELOG.md release $version has no entries." }

$relativeFiles = @(Get-Content -LiteralPath $fileManifestPath -Encoding UTF8 |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') })
if ($relativeFiles.Count -eq 0) { throw 'maxpkg-files.txt does not contain package files.' }

$packageFiles = New-Object System.Collections.Generic.List[object]
foreach ($relativeFile in $relativeFiles) {
    if ([IO.Path]::IsPathRooted($relativeFile) -or $relativeFile.Contains('..')) {
        throw "Unsafe package-relative path: $relativeFile"
    }
    $normalizedRelative = $relativeFile.Replace('/', '\')
    $absoluteFile = [IO.Path]::GetFullPath((Join-Path $projectRoot $normalizedRelative))
    if (-not $absoluteFile.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Package file escapes the project root: $relativeFile"
    }
    if (-not (Test-Path -LiteralPath $absoluteFile -PathType Leaf)) {
        throw "Required MaxPkg file is missing: $relativeFile"
    }
    $packageFiles.Add([pscustomobject]@{ Absolute = $absoluteFile; Relative = $normalizedRelative })
}

New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null

$settingsLines = New-Object System.Collections.Generic.List[string]
$settingsLines.Add('[settings]')
$settingsLines.Add('packageName=Max Ultra MCP')
$settingsLines.Add('buttonName=Max Ultra MCP')
$settingsLines.Add("packageGuid=$packageGuid")
$settingsLines.Add('description=Control already-open Autodesk 3ds Max instances from MCP-compatible AI clients.')
$settingsLines.Add('developerName=3DGROUND')
$settingsLines.Add('license=Free')
$settingsLines.Add('licenseUrl=')
$settingsLines.Add('documentation=https://github.com/maxpkg-dev/max-ultra-mcp#readme')
$settingsLines.Add('homepage=https://github.com/maxpkg-dev/max-ultra-mcp')
$settingsLines.Add('purchase=')
$settingsLines.Add('purchaseButtonLabel=Buy')
$settingsLines.Add('createMacroButton=true')
$settingsLines.Add('showInToolbar=true')
$settingsLines.Add('customInstallScript=')
$settingsLines.Add('customUninstallScript=' + (Join-Path $projectRoot 'scripts\maxpkg-uninstall.ms'))
$settingsLines.Add("outputFolder=$outputFolder")
$settingsLines.Add("svgIcon=$packagerIconPath")
$settingsLines.Add('entry=01_START_MAX_ULTRA_MCP_FIRST.ms')
$settingsLines.Add('compileEntry=false')
$settingsLines.Add("version=$version")
$settingsLines.Add("releaseChannel=$($projectVersion.Channel)")
$settingsLines.Add("releaseDate=$releaseDate")
$settingsLines.Add('min3dsMax=2022')
$settingsLines.Add('max3dsMax=2027')
$settingsLines.Add('')
$settingsLines.Add('[files]')
$settingsLines.Add('count=' + $packageFiles.Count)
for ($fileIndex = 0; $fileIndex -lt $packageFiles.Count; $fileIndex++) {
    $iniIndex = $fileIndex + 1
    $settingsLines.Add("${iniIndex}_abs=$($packageFiles[$fileIndex].Absolute)")
    $settingsLines.Add("${iniIndex}_rel=$($packageFiles[$fileIndex].Relative)")
}
$settingsLines.Add('')
$settingsLines.Add('[buildPathRules]')
$settingsLines.Add('count=0')
$settingsLines.Add('')
$settingsLines.Add('[extraMacros]')
$settingsLines.Add('count=0')

$changelogLines = New-Object System.Collections.Generic.List[string]
$changelogLines.Add("[version_$version]")
$changelogLines.Add("version=$version")
$changelogLines.Add("releaseDate=$releaseDate")
$changelogLines.Add("releaseChannel=$($projectVersion.Channel)")
$changelogLines.Add('min3dsMax=2022')
$changelogLines.Add("count=$($changelogEntries.Count)")
for ($entryIndex = 0; $entryIndex -lt $changelogEntries.Count; $entryIndex++) {
    $iniIndex = $entryIndex + 1
    $changelogLines.Add("${iniIndex}_type=$($changelogEntries[$entryIndex].Type)")
    $changelogLines.Add("${iniIndex}_text=$($changelogEntries[$entryIndex].Message)")
}

$utf8Bom = New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllLines($settingsPath, $settingsLines.ToArray(), $utf8Bom)
[IO.File]::WriteAllLines($changelogPath, $changelogLines.ToArray(), $utf8Bom)

Write-Host 'MaxPkg project files are ready. Run maxpkg-packager.ms in 3ds Max, review the metadata, and build the MZP.'
