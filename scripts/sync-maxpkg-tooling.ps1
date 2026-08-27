# Bootstraps missing MaxPkg tooling from a verified official revision without replacing self-updated files.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

[CmdletBinding()]
param([switch]$Force)

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
$revision = '3727cfd6fe98f8fa6bfd31b900f44ee0c37d9417'
$baseUri = "https://raw.githubusercontent.com/maxpkg-dev/max-dev-tool/$revision"
$toolFiles = [ordered]@{
    'maxpkg-packager.ms' = '8BE1C68508E2297F0CD5A89C9D51C3AEFBD1670DB5901249274C842D33BBD16B'
    '_install.ms' = '237663E6AE926A54605F5B0B52F7C9368903445DF21A642E001C2EFD7D0C883D'
    '_uninstall.ms' = 'C1082A7B3467EF0DD627B5722D54CB726028E317640821F5542528064D05A9CB'
}
$preservedFiles = New-Object System.Collections.Generic.List[string]
$downloadedFiles = New-Object System.Collections.Generic.List[string]
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('max-ultra-mcp-maxpkg-' + [Guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    foreach ($fileName in $toolFiles.Keys) {
        $destinationPath = Join-Path $projectRoot $fileName
        if (-not $Force -and (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
            $preservedFiles.Add($fileName)
            continue
        }
        $temporaryPath = Join-Path $temporaryRoot $fileName
        Invoke-WebRequest -Uri "$baseUri/$fileName" -OutFile $temporaryPath -UseBasicParsing
        $downloadHash = (Get-MaxUltraSha256Hash -LiteralPath $temporaryPath)
        if ($downloadHash -ne $toolFiles[$fileName]) {
            throw "MaxPkg tooling hash mismatch for $fileName."
        }
        Move-Item -LiteralPath $temporaryPath -Destination $destinationPath -Force
        $downloadedFiles.Add($fileName)
    }
    Write-Host "MaxPkg tooling is ready. Preserved existing: $($preservedFiles.Count); bootstrapped/restored from $($revision): $($downloadedFiles.Count)."
}
finally {
    if ((Test-Path -LiteralPath $temporaryRoot) -and $temporaryRoot.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
