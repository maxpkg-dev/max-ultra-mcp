# Parses the canonical stable Max Ultra MCP version.ini metadata.
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

function Get-MaxUltraProjectVersionInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VersionIniPath
    )

    if (-not (Test-Path -LiteralPath $VersionIniPath -PathType Leaf)) {
        throw "Version source is missing: $VersionIniPath"
    }
    $versionContent = [IO.File]::ReadAllText([IO.Path]::GetFullPath($VersionIniPath))
    $sectionMatch = [regex]::Match(
        $versionContent,
        '(?ms)^\[MaxUltraMCP\]\s*\r?\n(?<body>.*?)(?=^\[|\z)'
    )
    if (-not $sectionMatch.Success) {
        throw 'version.ini is missing the [MaxUltraMCP] section.'
    }
    $versionMatch = [regex]::Match($sectionMatch.Groups['body'].Value, '(?m)^Version=(?<value>[^\r\n]+)\s*$')
    $channelMatch = [regex]::Match($sectionMatch.Groups['body'].Value, '(?m)^Channel=(?<value>[^\r\n]+)\s*$')
    if (-not $versionMatch.Success -or -not $channelMatch.Success) {
        throw 'version.ini must define Version and Channel.'
    }
    $parsedVersion = ConvertTo-MaxUltraReleaseVersion -Text $versionMatch.Groups['value'].Value
    $channel = $channelMatch.Groups['value'].Value.Trim().ToLowerInvariant()
    if ($channel -ne 'stable') {
        throw "Unsupported release channel '$channel'."
    }
    return [pscustomobject]@{
        Version = $parsedVersion.Text
        VersionValue = $parsedVersion.Value
        Channel = $channel
    }
}
