param(
    [string]$Version = '1.0.0',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$resolvedOutput = [IO.Path]::GetFullPath($OutputDirectory)
$portableNode = Join-Path $projectRoot 'runtime\win-x64\node.exe'
if (-not (Test-Path -LiteralPath $portableNode -PathType Leaf)) {
    throw 'runtime\win-x64\node.exe is missing. Run scripts\prepare-portable-node.ps1 before building a release.'
}

$reportedNodeVersion = & $portableNode -p 'process.versions.node'
if ([Version]$reportedNodeVersion -lt [Version]'24.0.0') { throw "Release runtime must be Node.js 24+, found $reportedNodeVersion" }

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("max-ultra-mcp-release-" + [Guid]::NewGuid().ToString('N'))
$packageName = "Max-Ultra-MCP-v$Version-win-x64"
$stageRoot = Join-Path $temporaryRoot $packageName
$zipPath = Join-Path $resolvedOutput "$packageName.zip"

try {
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
    foreach ($directory in @('core','scripts','runtime','docs','examples')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $directory) -Destination $stageRoot -Recurse -Force
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot '01_START_MAX_ULTRA_MCP_FIRST.ms') -Destination $stageRoot
    Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination $stageRoot

    New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
    Compress-Archive -LiteralPath $stageRoot -DestinationPath $zipPath -CompressionLevel Optimal -Force
    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    Set-Content -LiteralPath "$zipPath.sha256" -Value "$hash  $([IO.Path]::GetFileName($zipPath))" -Encoding ASCII
    Write-Host "[3DGROUND | Max Ultra MCP] Release: $zipPath"
    Write-Host "[3DGROUND | Max Ultra MCP] SHA-256: $hash"
} finally {
    if ((Test-Path -LiteralPath $temporaryRoot) -and $temporaryRoot.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
