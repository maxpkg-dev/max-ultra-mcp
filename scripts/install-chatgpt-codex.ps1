param(
    [ValidateSet('core','archviz','full')][string]$Profile = 'archviz',
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA '3DGROUND\MaxUltraMCP'),
    [switch]$NoCopy,
    [switch]$ReplaceExisting
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$targetRoot = if ($NoCopy) { $sourceRoot } else { [IO.Path]::GetFullPath($InstallRoot) }

if (-not $NoCopy) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA is unavailable.' }
    $allowedRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA '3DGROUND'))
    if (-not $targetRoot.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "InstallRoot must stay below $allowedRoot"
    }
    $sourceNode = Join-Path $sourceRoot 'runtime\win-x64\node.exe'
    if (-not (Test-Path -LiteralPath $sourceNode -PathType Leaf)) {
        throw 'The release has no bundled runtime\win-x64\node.exe. Package it with scripts\prepare-portable-node.ps1 first.'
    }
    New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
    foreach ($directory in @('core','scripts','runtime','docs','examples')) {
        $source = Join-Path $sourceRoot $directory
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $targetRoot -Recurse -Force }
    }
    Copy-Item -LiteralPath (Join-Path $sourceRoot '01_START_MAX_ULTRA_MCP_FIRST.ms') -Destination $targetRoot -Force
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'README.md') -Destination $targetRoot -Force
}

$nodePath = Join-Path $targetRoot 'runtime\win-x64\node.exe'
if (-not (Test-Path -LiteralPath $nodePath -PathType Leaf)) {
    $nodeCommand = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($nodeCommand) { $nodePath = $nodeCommand.Source }
}
if (-not (Test-Path -LiteralPath $nodePath -PathType Leaf)) { throw 'No usable Node runtime was found.' }
$serverPath = Join-Path $targetRoot 'core\server.js'

$codex = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($codex) {
    if ($ReplaceExisting) {
        & $codex.Source mcp remove max-ultra-mcp 2>$null
    }
    & $codex.Source mcp add max-ultra-mcp --env "MAX_ULTRA_MCP_TOOL_PROFILE=$Profile" -- $nodePath $serverPath --stdio
    if ($LASTEXITCODE -ne 0) {
        throw 'Codex MCP registration failed. If max-ultra-mcp already exists, rerun with -ReplaceExisting.'
    }
    Write-Host '[3DGROUND | Max Ultra MCP] Registered for ChatGPT Desktop, Codex CLI, and the Codex IDE extension.'
} else {
    Write-Host 'Codex CLI was not found. In ChatGPT Desktop open Settings -> MCP servers -> Add server:'
    Write-Host '  Name    : max-ultra-mcp'
    Write-Host '  Type    : STDIO'
    Write-Host "  Command : $nodePath"
    Write-Host "  Args    : $serverPath --stdio"
    Write-Host "  Env     : MAX_ULTRA_MCP_TOOL_PROFILE=$Profile"
}

Write-Host "Run this file in each 3ds Max process: $(Join-Path $targetRoot '01_START_MAX_ULTRA_MCP_FIRST.ms')"
