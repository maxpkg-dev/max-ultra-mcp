# Validates and publishes one new MaxPkg MZP as an identity-bound GitHub Release.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
function Get-MaxUltraSha256Hash {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    $stream = [IO.File]::OpenRead([IO.Path]::GetFullPath($LiteralPath))
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '')
    }
    finally {
        $stream.Dispose()
        $algorithm.Dispose()
    }
}
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$versionIniPath = Join-Path $projectRoot 'version.ini'
$packageJsonPath = Join-Path $projectRoot 'core\package.json'
$distDirectory = Join-Path $projectRoot 'dist'
$expectedRepository = 'maxpkg-dev/max-ultra-mcp'
$expectedRemote = 'origin'
$expectedBranch = 'main'
$packageGuid = 'c6977570-25a6-41b0-b9bb-b3be8101123c'

. (Join-Path $PSScriptRoot 'release-mzp-utils.ps1')

function Invoke-ReleaseCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowEmptyOutput
    )

    $commandOutput = (& $Executable @Arguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $Executable $($Arguments -join ' ')`n$commandOutput"
    }
    if (-not $AllowEmptyOutput -and [string]::IsNullOrWhiteSpace($commandOutput)) {
        throw "Command returned no output: $Executable $($Arguments -join ' ')"
    }
    return $commandOutput
}

function Assert-MzpArchive {
    param(
        [Parameter(Mandatory = $true)]
        [IO.FileInfo]$PackageFile,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedVersion
    )

    if ($PackageFile.Length -lt 1MB) {
        throw "MZP is unexpectedly small: $($PackageFile.FullName)"
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($PackageFile.FullName)
    try {
        $requiredEntries = @(
            '01_START_MAX_ULTRA_MCP_FIRST.ms',
            'manifest.json',
            'runtime/win-x64/node.exe',
            'runtime/win-x64/NODE-LICENSE.txt'
        )
        $entriesByName = @{}
        foreach ($archiveEntry in $archive.Entries) {
            $entriesByName[$archiveEntry.FullName.Replace('\', '/')] = $archiveEntry
        }
        foreach ($requiredEntry in $requiredEntries) {
            if (-not $entriesByName.ContainsKey($requiredEntry)) {
                throw "MZP is missing required entry: $requiredEntry"
            }
        }
        if ($entriesByName['runtime/win-x64/node.exe'].Length -lt 1MB) {
            throw 'The bundled portable Node.js executable is unexpectedly small.'
        }
        $manifestReader = New-Object IO.StreamReader($entriesByName['manifest.json'].Open())
        try {
            $manifest = $manifestReader.ReadToEnd() | ConvertFrom-Json
        }
        finally {
            $manifestReader.Dispose()
        }
        if ([string]$manifest.version -ne $ExpectedVersion -or
            [string]$manifest.packageGuid -ne $packageGuid -or
            [string]$manifest.name -ne 'Max Ultra MCP') {
            throw 'The internal MZP manifest does not match the project version, package GUID, or product name.'
        }
    }
    finally {
        $archive.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) { throw 'core\package.json is missing.' }
$projectVersionInfo = Get-MaxUltraProjectVersionInfo -VersionIniPath $versionIniPath
$packageData = Get-Content -LiteralPath $packageJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
$projectVersion = $projectVersionInfo.Version
if ([string]$packageData.version -ne $projectVersion) {
    throw 'core\package.json does not match version.ini. Run scripts\prepare-release.ps1.'
}
$releaseTag = "v$projectVersion"

$allMzpFiles = if (Test-Path -LiteralPath $distDirectory -PathType Container) {
    @(Get-ChildItem -LiteralPath $distDirectory -Recurse -File -Filter '*.mzp')
} else {
    @()
}
$packages = @(Get-MaxUltraMzpPackages -DistDirectory $distDirectory)
foreach ($unrecognizedFile in $allMzpFiles | Where-Object { $_.FullName -notin @($packages | ForEach-Object { $_.File.FullName }) }) {
    Write-Warning "Ignoring MZP with an unsupported filename: $($unrecognizedFile.Name)"
}
$latestPackage = Get-LatestMaxUltraMzp -Packages $packages

$ghCommand = Get-Command gh -ErrorAction SilentlyContinue
if ($null -eq $ghCommand) {
    throw 'GitHub CLI is not installed. Install gh, run gh auth login, and retry.'
}
& $ghCommand.Source auth status --hostname github.com *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'GitHub CLI is not authenticated. Run gh auth login and retry.'
}
$releaseJson = Invoke-ReleaseCommand -Executable $ghCommand.Source -Arguments @(
    'release', 'list', '--repo', $expectedRepository, '--limit', '100',
    '--json', 'tagName,isDraft,isPrerelease,publishedAt'
) -AllowEmptyOutput
$releaseRecords = if ([string]::IsNullOrWhiteSpace($releaseJson)) { @() } else { @($releaseJson | ConvertFrom-Json) }
$latestGitHubRelease = Get-LatestMaxUltraGitHubRelease -Releases $releaseRecords

Write-Host ''
Write-Host '[3DGROUND | Max Ultra MCP] GitHub MZP release check'
Write-Host "  Project version       : $projectVersion"
Write-Host ('  Latest local MZP      : ' + $(if ($null -eq $latestPackage) { '<none>' } else { $latestPackage.Version + ' | ' + $latestPackage.File.Name }))
Write-Host ('  Latest GitHub release : ' + $(if ($null -eq $latestGitHubRelease) { '<none>' } else { $latestGitHubRelease.TagName }))
Write-Host ''

if ($null -eq $latestPackage) {
    throw "No valid Max Ultra MCP MZP was found below $distDirectory. Build version $projectVersion with MaxPkg Packager first."
}
if ($latestPackage.VersionValue.CompareTo([Version]$projectVersion) -lt 0) {
    throw "The latest local MZP is $($latestPackage.Version), but the project is $projectVersion. Rebuild the MZP before releasing."
}
if ($latestPackage.VersionValue.CompareTo([Version]$projectVersion) -gt 0) {
    throw "The latest local MZP is newer than version.ini. Prepare the intended release version deliberately."
}
$currentVersionPackages = @($packages | Where-Object { $_.Version -eq $projectVersion })
if ($currentVersionPackages.Count -ne 1) {
    throw "Expected exactly one MZP for version $projectVersion, found $($currentVersionPackages.Count)."
}
$releasePackage = $currentVersionPackages[0].File
Assert-MzpArchive -PackageFile $releasePackage -ExpectedVersion $projectVersion

if ($null -ne $latestGitHubRelease -and $latestGitHubRelease.VersionValue.CompareTo([Version]$projectVersion) -gt 0) {
    throw "GitHub already contains newer release $($latestGitHubRelease.TagName). Refusing to publish an older version."
}
$matchingRemoteRelease = @($releaseRecords | Where-Object {
    [string]::Equals([string]$_.tagName, $releaseTag, [StringComparison]::OrdinalIgnoreCase) -or
    [string]::Equals([string]$_.tagName, $projectVersion, [StringComparison]::OrdinalIgnoreCase)
})
if ($matchingRemoteRelease.Count -gt 0) {
    $existingJson = Invoke-ReleaseCommand -Executable $ghCommand.Source -Arguments @(
        'release', 'view', ([string]$matchingRemoteRelease[0].tagName), '--repo', $expectedRepository,
        '--json', 'url,assets'
    )
    $existingRelease = $existingJson | ConvertFrom-Json
    $matchingAsset = @($existingRelease.assets | Where-Object { $_.name -eq $releasePackage.Name })
    if ($matchingAsset.Count -eq 1) {
        Write-Host "Release $releaseTag already contains $($releasePackage.Name). Nothing was published."
        Write-Host $existingRelease.url
        exit 0
    }
    throw "Release $releaseTag already exists but does not contain $($releasePackage.Name). Refusing to mutate an existing release automatically."
}

$gitCommand = (Get-Command git -ErrorAction Stop).Source
$remoteUrl = Invoke-ReleaseCommand -Executable $gitCommand -Arguments @('remote', 'get-url', $expectedRemote)
if ($remoteUrl -notmatch 'github\.com[:/]maxpkg-dev/max-ultra-mcp(?:\.git)?$') {
    throw "Remote '$expectedRemote' does not point to $expectedRepository."
}
$branchName = Invoke-ReleaseCommand -Executable $gitCommand -Arguments @('branch', '--show-current')
if ($branchName -ne $expectedBranch) {
    throw "Releases must be created from $expectedBranch, current branch is '$branchName'."
}
$workingTreeState = Invoke-ReleaseCommand -Executable $gitCommand -Arguments @('status', '--porcelain', '--untracked-files=all') -AllowEmptyOutput
if (-not [string]::IsNullOrWhiteSpace($workingTreeState)) {
    throw 'The Git working tree is not clean. Commit the release sources before publishing.'
}
$headCommit = Invoke-ReleaseCommand -Executable $gitCommand -Arguments @('rev-parse', 'HEAD')
$remoteHeadLine = Invoke-ReleaseCommand -Executable $gitCommand -Arguments @('ls-remote', '--heads', $expectedRemote, "refs/heads/$expectedBranch")
$remoteHeadCommit = ($remoteHeadLine -split '\s+')[0]
if ($headCommit -ne $remoteHeadCommit) {
    throw "Local HEAD is not the published $expectedRemote/$expectedBranch commit. Push the source commit before creating the release."
}

$checksumPath = $releasePackage.FullName + '.sha256'
$checksum = (Get-MaxUltraSha256Hash -LiteralPath $releasePackage.FullName).ToLowerInvariant()
$checksumLine = "$checksum  $($releasePackage.Name)`n"
[IO.File]::WriteAllText($checksumPath, $checksumLine, (New-Object Text.UTF8Encoding($false)))

Write-Host "Ready to create $releaseTag from commit $headCommit"
Write-Host "  Asset: $($releasePackage.FullName)"
Write-Host "  SHA256: $checksum"
if ($CheckOnly) {
    Write-Host 'Check-only mode completed. No GitHub release was created.'
    exit 0
}
if (-not $Yes) {
    $confirmation = Read-Host "Publish $releaseTag to GitHub? [Y/N]"
    if ($confirmation.Trim().ToUpperInvariant() -ne 'Y') {
        throw 'Release cancelled. Nothing was published.'
    }
}

& $ghCommand.Source release create $releaseTag $releasePackage.FullName $checksumPath `
    --repo $expectedRepository `
    --target $headCommit `
    --title "Max Ultra MCP $projectVersion" `
    --generate-notes `
    --latest
if ($LASTEXITCODE -ne 0) {
    throw 'GitHub CLI failed to create the release.'
}
$publishedJson = Invoke-ReleaseCommand -Executable $ghCommand.Source -Arguments @(
    'release', 'view', $releaseTag, '--repo', $expectedRepository, '--json', 'url,assets'
)
$publishedRelease = $publishedJson | ConvertFrom-Json
$publishedAssetNames = @($publishedRelease.assets | ForEach-Object { $_.name })
if ($releasePackage.Name -notin $publishedAssetNames -or (Split-Path -Leaf $checksumPath) -notin $publishedAssetNames) {
    throw 'The release was created, but one or more expected assets are missing. Inspect the release before retrying.'
}
Write-Host "Published ${releaseTag}: $($publishedRelease.url)"
