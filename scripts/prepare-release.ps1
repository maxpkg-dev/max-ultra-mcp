# Synchronizes version metadata and promotes the reviewed Unreleased changelog for a local release.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

[CmdletBinding()]
param(
    [string]$Version,

    [ValidateSet('stable')]
    [string]$Channel = 'stable',


    [switch]$SkipTests,
    [switch]$SkipMaxPkgPreparation
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$versionIniPath = Join-Path $projectRoot 'version.ini'
$packageJsonPath = Join-Path $projectRoot 'core\package.json'
$pluginManifestPath = Join-Path $projectRoot 'plugins\max-ultra-mcp\.codex-plugin\plugin.json'
$changelogPath = Join-Path $projectRoot 'CHANGELOG.md'

. (Join-Path $PSScriptRoot 'release-mzp-utils.ps1')

$releaseDate = [DateTime]::UtcNow.ToString('yyyy-MM-dd')
$utf8WithoutBom = New-Object Text.UTF8Encoding($false)

foreach ($requiredPath in @($versionIniPath, $packageJsonPath, $pluginManifestPath, $changelogPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required release source is missing: $requiredPath"
    }
}

$currentInfo = Get-MaxUltraProjectVersionInfo -VersionIniPath $versionIniPath
$releaseVersion = if ([string]::IsNullOrWhiteSpace($Version)) {
    $currentInfo.Version
}
else {
    (ConvertTo-MaxUltraReleaseVersion -Text $Version).Text
}
if ($currentInfo.VersionValue.CompareTo([Version]$releaseVersion) -gt 0) {
    throw "The requested version $releaseVersion is older than $($currentInfo.Version)."
}

$changelogContent = [IO.File]::ReadAllText($changelogPath)
$unreleasedMatch = [regex]::Match(
    $changelogContent,
    '(?ms)^## Unreleased\s*\r?\n(?<body>.*?)(?=^## |\z)'
)
if (-not $unreleasedMatch.Success) {
    throw 'CHANGELOG.md must contain a top-level ## Unreleased section.'
}
$unreleasedBody = $unreleasedMatch.Groups['body'].Value.Trim()
$existingReleaseMatch = [regex]::Match(
    $changelogContent,
    "(?m)^## $([regex]::Escape($releaseVersion)) - [0-9]{4}-[0-9]{2}-[0-9]{2}\s*$"
)
$isPreparedRetry = (
    $currentInfo.Version -eq $releaseVersion -and
    $existingReleaseMatch.Success -and
    [string]::IsNullOrWhiteSpace($unreleasedBody)
)
if ([string]::IsNullOrWhiteSpace($unreleasedBody) -and -not $isPreparedRetry) {
    throw 'CHANGELOG.md Unreleased is empty. Add factual release notes before preparing a release.'
}
foreach ($entryLine in $unreleasedBody -split '\r?\n') {
    if ([string]::IsNullOrWhiteSpace($entryLine)) { continue }
    if ($entryLine -notmatch '^- (Added|Changed|Improved|Fixed|Removed): .+') {
        throw "Unsupported changelog entry: $entryLine"
    }
}
if ($existingReleaseMatch.Success -and -not $isPreparedRetry) {
    throw "CHANGELOG.md already contains version $releaseVersion."
}

$versionIniContent = "[MaxUltraMCP]`r`nVersion=$releaseVersion`r`nChannel=$Channel`r`n"
[IO.File]::WriteAllText($versionIniPath, $versionIniContent, $utf8WithoutBom)

$packageJsonContent = [IO.File]::ReadAllText($packageJsonPath)
try { $packageJsonContent | ConvertFrom-Json | Out-Null } catch { throw 'core\package.json is not valid JSON.' }
$packageVersionMatches = [regex]::Matches($packageJsonContent, '(?m)^(?<prefix>\s*"version"\s*:\s*")[^"]+(?<suffix>",?\s*)$')
if ($packageVersionMatches.Count -ne 1) { throw 'core\package.json must contain exactly one top-level version line.' }
$packageVersionMatch = $packageVersionMatches[0]
$packageVersionLine = $packageVersionMatch.Groups['prefix'].Value + $releaseVersion + $packageVersionMatch.Groups['suffix'].Value
$packageJsonContent = $packageJsonContent.Remove($packageVersionMatch.Index, $packageVersionMatch.Length).Insert($packageVersionMatch.Index, $packageVersionLine)
[IO.File]::WriteAllText($packageJsonPath, $packageJsonContent, $utf8WithoutBom)

$pluginManifest = Get-Content -Raw -LiteralPath $pluginManifestPath | ConvertFrom-Json
if ([string]$pluginManifest.name -ne 'max-ultra-mcp') { throw 'The Codex plugin manifest has an unexpected name.' }
$pluginManifest.version = $releaseVersion
[IO.File]::WriteAllText($pluginManifestPath, (($pluginManifest | ConvertTo-Json -Depth 10) + "`n"), $utf8WithoutBom)

if (-not $isPreparedRetry) {
    $releasedSection = "## $releaseVersion - $releaseDate`r`n`r`n$unreleasedBody`r`n`r`n"
    $newUnreleasedSection = "## Unreleased`r`n`r`n"
    $newChangelogContent = $changelogContent.Remove($unreleasedMatch.Index, $unreleasedMatch.Length).Insert(
        $unreleasedMatch.Index,
        $newUnreleasedSection + $releasedSection
    )
    [IO.File]::WriteAllText($changelogPath, $newChangelogContent, $utf8WithoutBom)
}

if (-not $SkipMaxPkgPreparation) {
    & (Join-Path $PSScriptRoot 'prepare-maxpkg.ps1')
}
if (-not $SkipTests) {
    & (Join-Path $PSScriptRoot 'run-smoke.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Verification failed with exit code $LASTEXITCODE." }
}

Write-Host "Max Ultra MCP $releaseVersion sources and MaxPkg inputs are prepared locally. Review them, build and test the MZP, then commit the release. No push or GitHub release was created."
