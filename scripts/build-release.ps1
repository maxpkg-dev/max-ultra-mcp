# Prepares the only supported release workflow through MaxPkg Packager.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$portableNode = Join-Path $projectRoot 'runtime\win-x64\node.exe'
if (-not (Test-Path -LiteralPath $portableNode -PathType Leaf)) {
    throw 'runtime\win-x64\node.exe is missing. Run scripts\prepare-portable-node.ps1 before building a release.'
}

$reportedNodeVersion = & $portableNode -p 'process.versions.node'
if ([Version]$reportedNodeVersion -lt [Version]'24.0.0') { throw "Release runtime must be Node.js 24+, found $reportedNodeVersion" }
& (Join-Path $PSScriptRoot 'prepare-maxpkg.ps1')
Write-Host '[3DGROUND | Max Ultra MCP] MaxPkg release project prepared. Run maxpkg-packager.ms in 3ds Max and choose Build MZP.'
