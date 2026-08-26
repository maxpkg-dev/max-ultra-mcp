# Downloads one pinned MaxPkg Packager release and verifies every file before use.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$revision = '561d0a882ad42eb29dcc04b7f950d02c33d09cc4'
$baseUri = "https://raw.githubusercontent.com/maxpkg-dev/max-dev-tool/$revision"
$toolFiles = [ordered]@{
    'maxpkg-packager.ms' = '104756885DACE63103624F7B89EA86E2FFC3FCE7CCA85DB1120DD7D3C9FB364C'
    '_install.ms' = '237663E6AE926A54605F5B0B52F7C9368903445DF21A642E001C2EFD7D0C883D'
    '_uninstall.ms' = 'C1082A7B3467EF0DD627B5722D54CB726028E317640821F5542528064D05A9CB'
}
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('max-ultra-mcp-maxpkg-' + [Guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    foreach ($fileName in $toolFiles.Keys) {
        $destinationPath = Join-Path $projectRoot $fileName
        if (-not $Force -and (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
            $existingHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
            if ($existingHash -eq $toolFiles[$fileName]) { continue }
        }

        $temporaryPath = Join-Path $temporaryRoot $fileName
        Invoke-WebRequest -Uri "$baseUri/$fileName" -OutFile $temporaryPath -UseBasicParsing
        $downloadHash = (Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256).Hash
        if ($downloadHash -ne $toolFiles[$fileName]) {
            throw "MaxPkg tooling hash mismatch for $fileName."
        }
        Move-Item -LiteralPath $temporaryPath -Destination $destinationPath -Force
    }
    Write-Host "MaxPkg tooling $revision is ready."
}
finally {
    if ((Test-Path -LiteralPath $temporaryRoot) -and $temporaryRoot.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
