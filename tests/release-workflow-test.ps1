# Verifies release-version and MaxPkg MZP filename parsing without accessing GitHub.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $projectRoot 'scripts\release-mzp-utils.ps1')

function Assert-ReleaseTest {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('max-ultra-mcp-release-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $temporaryRoot 'maxpkg') -Force | Out-Null
try {
    $packageGuid = 'c6977570-25a6-41b0-b9bb-b3be8101123c'
    New-Item -ItemType File -Path (Join-Path $temporaryRoot "max-ultra-mcp@1.0.0@$packageGuid.mzp") | Out-Null
    New-Item -ItemType File -Path (Join-Path $temporaryRoot "max-ultra-mcp@1.2.0@$packageGuid.mzp") | Out-Null
    New-Item -ItemType File -Path (Join-Path $temporaryRoot 'maxpkg\unrelated-package@9.0.0@00000000-0000-0000-0000-000000000000.mzp') | Out-Null

    $packages = @(Get-MaxUltraMzpPackages -DistDirectory $temporaryRoot)
    Assert-ReleaseTest ($packages.Count -eq 2) 'Only exact Max Ultra MCP package filenames should be accepted.'
    $latestPackage = Get-LatestMaxUltraMzp -Packages $packages
    Assert-ReleaseTest ($latestPackage.Version -eq '1.2.0') 'The highest local MZP version was not selected.'

    $releaseRecords = @(
        [pscustomobject]@{ tagName = 'v1.0.0'; isDraft = $false; isPrerelease = $false },
        [pscustomobject]@{ tagName = 'v1.3.0'; isDraft = $false; isPrerelease = $false },
        [pscustomobject]@{ tagName = 'v2.0.0'; isDraft = $true; isPrerelease = $false },
        [pscustomobject]@{ tagName = 'preview'; isDraft = $false; isPrerelease = $false }
    )
    $latestRelease = Get-LatestMaxUltraGitHubRelease -Releases $releaseRecords
    Assert-ReleaseTest ($latestRelease.Version -eq '1.3.0') 'Draft and invalid tags must not replace the latest stable release.'

    $invalidVersionRejected = $false
    try {
        ConvertTo-MaxUltraReleaseVersion -Text '1.2' | Out-Null
    }
    catch {
        $invalidVersionRejected = $true
    }
    Assert-ReleaseTest $invalidVersionRejected 'Incomplete versions must be rejected.'
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Host 'Max Ultra MCP release workflow test passed: local MZP and GitHub version selection.'
