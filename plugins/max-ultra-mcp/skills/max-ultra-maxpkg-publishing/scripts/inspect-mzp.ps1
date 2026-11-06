# Prints the release facts, size, and SHA-256 of a built MaxPkg MZP without extracting or changing it.
# The output is private: it contains the package file name, which includes the package GUID.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'
$archivePath = [IO.Path]::GetFullPath($Path)
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { throw "MZP was not found: $Path" }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $manifestEntry = @($archive.Entries | Where-Object { $_.Name -ieq 'manifest.json' } | Sort-Object { $_.FullName.Length }) | Select-Object -First 1
    if (-not $manifestEntry) { throw 'manifest.json was not found in the archive.' }
    $reader = New-Object IO.StreamReader($manifestEntry.Open(), (New-Object Text.UTF8Encoding($false)))
    try { $manifestText = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $entryCount = $archive.Entries.Count
} finally {
    $archive.Dispose()
}

$manifest = $manifestText | ConvertFrom-Json
$fileName = [IO.Path]::GetFileName($archivePath)
$fileInfo = Get-Item -LiteralPath $archivePath
$sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
$problems = @()
$warnings = @()

if ($fileName -match '^(?<slug>[^@]+)@(?<version>\d+\.\d+\.\d+)@(?<guid>[^@]+)\.mzp$') {
    if ($Matches['version'] -ne [string]$manifest.version) { $problems += "The file name version $($Matches['version']) differs from manifest version $($manifest.version)." }
    if ($Matches['guid'] -ne [string]$manifest.packageGuid) { $problems += 'The file name GUID differs from the manifest packageGuid.' }
} else {
    $problems += 'The file name is not the original packager name <slug>@<major.minor.patch>@<guid>.mzp.'
}
if ([string]$manifest.releaseChannel -ne 'stable') { $problems += "releaseChannel is '$($manifest.releaseChannel)'; only stable versions appear in the public catalog." }
if ([string]::IsNullOrWhiteSpace([string]$manifest.description)) { $problems += 'description is empty; set the final short description and rebuild.' }
$minimumYear = 0
if (-not [int]::TryParse([string]$manifest.min3dsMax, [ref]$minimumYear)) {
    $problems += 'min3dsMax is missing or not a year.'
} elseif ($minimumYear -le 2012) {
    $warnings += "min3dsMax is $minimumYear, the packager fallback; confirm that this minimum is intended."
}
$maximumYear = 0
if ([int]::TryParse([string]$manifest.max3dsMax, [ref]$maximumYear) -and $minimumYear -gt $maximumYear) { $problems += 'min3dsMax is greater than max3dsMax.' }

[pscustomobject][ordered]@{
    file = $fileName
    size = $fileInfo.Length
    sha256 = $sha256
    entries = $entryCount
    name = $manifest.name
    version = $manifest.version
    releaseChannel = $manifest.releaseChannel
    releaseDate = $manifest.releaseDate
    min3dsMax = $manifest.min3dsMax
    max3dsMax = $manifest.max3dsMax
    description = $manifest.description
    license = $manifest.license
    developerName = $manifest.developerName
    homepage = $manifest.homepage
    documentation = $manifest.documentation
    purchase = $manifest.purchase
    ready = ($problems.Count -eq 0)
    problems = @($problems)
    warnings = @($warnings)
} | ConvertTo-Json -Depth 4
