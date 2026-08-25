param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\dist\max-ultra-mcp.exe')
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$portableNode = Join-Path $projectRoot 'runtime\win-x64\node.exe'
if (-not (Test-Path -LiteralPath $portableNode -PathType Leaf)) { throw 'Prepare portable Node first.' }
$npx = Get-Command npx -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $npx) { throw 'Experimental SEA build requires maintainer-side npx for esbuild and postject. End users never need npx.' }

$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("max-ultra-mcp-sea-" + [Guid]::NewGuid().ToString('N'))
$bundlePath = Join-Path $temporaryRoot 'max-ultra-mcp-bundle.cjs'
$blobPath = Join-Path $temporaryRoot 'max-ultra-mcp.blob'
$configPath = Join-Path $temporaryRoot 'sea-config.json'

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    & $npx.Source --yes esbuild (Join-Path $projectRoot 'core\server.js') --bundle --platform=node --format=cjs --target=node24 --outfile=$bundlePath
    if ($LASTEXITCODE -ne 0) { throw 'esbuild failed.' }
    [ordered]@{ main = $bundlePath; output = $blobPath; disableExperimentalSEAWarning = $true } | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding UTF8
    & $portableNode --experimental-sea-config $configPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $blobPath)) { throw 'Node SEA blob generation failed.' }

    New-Item -ItemType Directory -Path (Split-Path $resolvedOutput -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $portableNode -Destination $resolvedOutput -Force
    & $npx.Source --yes postject $resolvedOutput NODE_SEA_BLOB $blobPath --sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2
    if ($LASTEXITCODE -ne 0) { throw 'postject failed.' }
    Write-Host "[3DGROUND | Max Ultra MCP] Experimental SEA executable: $resolvedOutput"
    Write-Host 'Sign the resulting PE before distribution. Keep scripts\ beside the executable for UI/capture helpers.'
} finally {
    if ((Test-Path -LiteralPath $temporaryRoot) -and $temporaryRoot.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
