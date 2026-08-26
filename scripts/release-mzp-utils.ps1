# Parses and compares stable Max Ultra MCP release versions and MZP filenames.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

function ConvertTo-MaxUltraReleaseVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [switch]$AllowTagPrefix
    )

    $normalized = $Text.Trim()
    if ($AllowTagPrefix -and $normalized.StartsWith('v', [StringComparison]::OrdinalIgnoreCase)) {
        $normalized = $normalized.Substring(1)
    }
    if ($normalized -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
        throw "Unsupported release version '$Text'. Use stable semantic versioning such as 1.2.3."
    }
    return [pscustomobject]@{
        Text = $normalized
        Value = [Version]$normalized
    }
}

function Get-MaxUltraMzpInfo {
    param(
        [Parameter(Mandatory = $true)]
        [IO.FileInfo]$File
    )

    $packageGuid = 'c6977570-25a6-41b0-b9bb-b3be8101123c'
    $match = [regex]::Match(
        $File.Name,
        '^max-ultra-mcp@(?<version>(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))@(?<guid>[0-9a-fA-F-]{36})\.mzp$',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if (-not $match.Success -or
        -not [string]::Equals($match.Groups['guid'].Value, $packageGuid, [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    $parsedVersion = ConvertTo-MaxUltraReleaseVersion -Text $match.Groups['version'].Value
    return [pscustomobject]@{
        File = $File
        Version = $parsedVersion.Text
        VersionValue = $parsedVersion.Value
        PackageGuid = $packageGuid
    }
}

function Get-MaxUltraMzpPackages {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DistDirectory
    )

    if (-not (Test-Path -LiteralPath $DistDirectory -PathType Container)) {
        return @()
    }
    $packages = New-Object System.Collections.Generic.List[object]
    foreach ($candidateFile in Get-ChildItem -LiteralPath $DistDirectory -Recurse -File -Filter '*.mzp') {
        $packageInfo = Get-MaxUltraMzpInfo -File $candidateFile
        if ($null -ne $packageInfo) {
            $packages.Add($packageInfo)
        }
    }
    return @($packages.ToArray())
}

function Get-LatestMaxUltraMzp {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Packages
    )

    if ($Packages.Count -eq 0) {
        return $null
    }
    return $Packages | Sort-Object VersionValue -Descending | Select-Object -First 1
}

function Get-LatestMaxUltraGitHubRelease {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Releases
    )

    $stableReleases = New-Object System.Collections.Generic.List[object]
    foreach ($releaseRecord in $Releases) {
        if ($null -eq $releaseRecord -or $releaseRecord.isDraft -or $releaseRecord.isPrerelease) {
            continue
        }
        try {
            $parsedVersion = ConvertTo-MaxUltraReleaseVersion -Text ([string]$releaseRecord.tagName) -AllowTagPrefix
            $stableReleases.Add([pscustomobject]@{
                TagName = [string]$releaseRecord.tagName
                Version = $parsedVersion.Text
                VersionValue = $parsedVersion.Value
                Release = $releaseRecord
            })
        }
        catch {
            continue
        }
    }
    if ($stableReleases.Count -eq 0) {
        return $null
    }
    return $stableReleases.ToArray() | Sort-Object VersionValue -Descending | Select-Object -First 1
}
