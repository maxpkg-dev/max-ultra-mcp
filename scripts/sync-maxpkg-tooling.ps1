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
$revision = 'dec469a8791d7e1d2ec978c3ea1668c0fce1158e'
$baseUri = "https://raw.githubusercontent.com/maxpkg-dev/max-dev-tool/$revision"
$toolFiles = [ordered]@{
    'maxpkg-packager.ms' = '6076D58B41FDCB822780AC5A99F1F93966972BF21FF63294274943221D5E0CAB'
    '_install.ms' = 'EBC8AE14F136AF7F3F9D25C89A33886074672C4F7A331C94DA5222C3A3C7EBE9'
    '_uninstall.ms' = '2A17800E8F777474857733496A2A6C853332BD038437971171282F76B02B01F1'
}
# MaxPkg Packager 2.x keeps only its launcher in the project root; the standard hooks live in max-package.
$supportFolder = Join-Path $projectRoot 'max-package'
$toolFolders = @{
    'maxpkg-packager.ms' = $projectRoot
    '_install.ms' = $supportFolder
    '_uninstall.ms' = $supportFolder
}
$preservedFiles = New-Object System.Collections.Generic.List[string]
$downloadedFiles = New-Object System.Collections.Generic.List[string]
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('max-ultra-mcp-maxpkg-' + [Guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    foreach ($fileName in $toolFiles.Keys) {
        $destinationPath = Join-Path $toolFolders[$fileName] $fileName
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
        New-Item -ItemType Directory -Path $toolFolders[$fileName] -Force | Out-Null
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
