param(
    [string]$NodeVersion = '24.18.0',
    [switch]$Force
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
$destination = [IO.Path]::GetFullPath((Join-Path $projectRoot 'runtime\win-x64'))
if (-not $destination.StartsWith($projectRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Portable runtime destination escaped the project root.'
}

$nodeExecutable = Join-Path $destination 'node.exe'
if ((Test-Path -LiteralPath $nodeExecutable) -and -not $Force) {
    throw "Portable Node already exists at $nodeExecutable. Use -Force to replace it deliberately."
}

$archiveName = "node-v$NodeVersion-win-x64.zip"
$baseUrl = "https://nodejs.org/dist/v$NodeVersion"
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("max-ultra-mcp-node-" + [Guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $temporaryRoot $archiveName
$checksumsPath = Join-Path $temporaryRoot 'SHASUMS256.txt'
$extractPath = Join-Path $temporaryRoot 'extract'

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    Invoke-WebRequest -Uri "$baseUrl/SHASUMS256.txt" -OutFile $checksumsPath -UseBasicParsing
    Invoke-WebRequest -Uri "$baseUrl/$archiveName" -OutFile $archivePath -UseBasicParsing

    $checksumLine = Get-Content -LiteralPath $checksumsPath | Where-Object { $_ -match "\s+$([regex]::Escape($archiveName))$" } | Select-Object -First 1
    if (-not $checksumLine) { throw "Official SHASUMS256.txt does not contain $archiveName" }
    $expectedHash = ($checksumLine -split '\s+')[0].ToUpperInvariant()
    $actualHash = (Get-MaxUltraSha256Hash -LiteralPath $archivePath).ToUpperInvariant()
    if ($actualHash -ne $expectedHash) { throw "Node archive SHA-256 mismatch. Expected $expectedHash, received $actualHash" }

    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force
    $sourceRoot = Join-Path $extractPath "node-v$NodeVersion-win-x64"
    $sourceNode = Join-Path $sourceRoot 'node.exe'
    $sourceLicense = Join-Path $sourceRoot 'LICENSE'
    if (-not (Test-Path -LiteralPath $sourceNode -PathType Leaf)) { throw 'Official archive did not contain node.exe' }
    if (-not (Test-Path -LiteralPath $sourceLicense -PathType Leaf)) { throw 'Official archive did not contain LICENSE' }

    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Copy-Item -LiteralPath $sourceNode -Destination $nodeExecutable -Force
    Copy-Item -LiteralPath $sourceLicense -Destination (Join-Path $destination 'NODE-LICENSE.txt') -Force
    Set-Content -LiteralPath (Join-Path $destination 'VERSION.txt') -Value "v$NodeVersion" -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $destination 'SHA256.txt') -Value "$actualHash  $archiveName" -Encoding ASCII

    $installedVersion = & $nodeExecutable -p 'process.versions.node'
    if ($installedVersion -ne $NodeVersion) { throw "Installed node.exe reports $installedVersion instead of $NodeVersion" }
    Write-Host "[3DGROUND | Max Ultra MCP] Portable Node v$installedVersion prepared at $destination"
} finally {
    if ((Test-Path -LiteralPath $temporaryRoot) -and $temporaryRoot.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
