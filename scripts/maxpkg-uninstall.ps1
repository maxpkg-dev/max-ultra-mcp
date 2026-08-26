# Removes AI-client registrations and stops only Node processes launched from this package.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$PackageRoot)

$ErrorActionPreference = 'Stop'
$resolvedPackageRoot = [IO.Path]::GetFullPath($PackageRoot)
$serverPath = [IO.Path]::GetFullPath((Join-Path $resolvedPackageRoot 'core\server.js'))
$manifestPath = Join-Path $resolvedPackageRoot 'manifest.ini'
if (-not $serverPath.StartsWith($resolvedPackageRoot, [StringComparison]::OrdinalIgnoreCase) -or
    -not (Test-Path -LiteralPath $serverPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'The supplied folder is not an installed Max Ultra MCP package.'
}

function Resolve-ClientCommandPath([string]$ClientId, [string]$ExecutableName) {
    $clientCommand = Get-Command $ExecutableName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($clientCommand -and $clientCommand.Source) { return $clientCommand.Source }
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($ClientId -eq 'openai' -and -not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $codexBinRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
        if (Test-Path -LiteralPath $codexBinRoot -PathType Container) {
            Get-ChildItem -LiteralPath $codexBinRoot -Directory -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                ForEach-Object { $candidates.Add((Join-Path $_.FullName 'codex.exe')) }
        }
    }
    if ($ClientId -eq 'claudeCode') {
        if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
            $candidates.Add((Join-Path $env:USERPROFILE '.local\bin\claude.exe'))
        }
        if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
            $candidates.Add((Join-Path $env:APPDATA 'npm\claude.cmd'))
        }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Invoke-OptionalClientRemoval([string]$ClientId, [string]$ExecutableName, [string[]]$Arguments) {
    $clientPath = Resolve-ClientCommandPath $ClientId $ExecutableName
    if ([string]::IsNullOrWhiteSpace($clientPath)) { return }
    try { & $clientPath @Arguments 2>$null | Out-Null } catch {}
}

Invoke-OptionalClientRemoval 'openai' 'codex' @('mcp','remove','max-ultra-mcp')
Invoke-OptionalClientRemoval 'claudeCode' 'claude' @('mcp','remove','max-ultra-mcp','--scope','user')

$escapedServerPath = [Regex]::Escape($serverPath)
$ownedProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -and [Regex]::IsMatch([string]$_.CommandLine, $escapedServerPath, [Text.RegularExpressions.RegexOptions]::IgnoreCase) })
foreach ($ownedProcess in $ownedProcesses) {
    $currentProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($ownedProcess.ProcessId)" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $currentProcess -or -not [Regex]::IsMatch([string]$currentProcess.CommandLine, $escapedServerPath, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) { continue }
    Stop-Process -Id $ownedProcess.ProcessId -Force -ErrorAction Stop
}

$deadline = [DateTime]::UtcNow.AddSeconds(5)
do {
    $remaining = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -and [Regex]::IsMatch([string]$_.CommandLine, $escapedServerPath, [Text.RegularExpressions.RegexOptions]::IgnoreCase) })
    if ($remaining.Count -eq 0) { exit 0 }
    Start-Sleep -Milliseconds 100
} while ([DateTime]::UtcNow -lt $deadline)

throw 'Package-owned Max Ultra MCP processes did not stop within five seconds.'
