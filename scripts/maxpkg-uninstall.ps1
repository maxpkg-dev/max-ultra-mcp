# Removes AI-client registrations and stops only Node processes launched from this package.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$PackageRoot)

$ErrorActionPreference = 'Stop'
trap {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}

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

function Get-PackageOwnedNodeProcesses {
    return @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -and
            [Regex]::IsMatch([string]$_.CommandLine, $escapedServerPath, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        })
}

function Stop-PackageOwnedNodeProcess($OwnedProcess) {
    $currentProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($OwnedProcess.ProcessId)" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $currentProcess -or
        -not [Regex]::IsMatch([string]$currentProcess.CommandLine, $escapedServerPath, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        return
    }

    try {
        Stop-Process -Id $currentProcess.ProcessId -Force -ErrorAction Stop
    } catch {
        $recheckedProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($currentProcess.ProcessId)" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $recheckedProcess -and
            [Regex]::IsMatch([string]$recheckedProcess.CommandLine, $escapedServerPath, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            throw "Could not stop a package-owned Max Ultra MCP process. Close connected AI clients and try again."
        }
    }
}

$deadline = [DateTime]::UtcNow.AddSeconds(10)
$quietSince = $null
do {
    $ownedProcesses = @(Get-PackageOwnedNodeProcesses)
    if ($ownedProcesses.Count -eq 0) {
        if ($null -eq $quietSince) { $quietSince = [DateTime]::UtcNow }
        if (([DateTime]::UtcNow - $quietSince).TotalMilliseconds -ge 750) { exit 0 }
    } else {
        $quietSince = $null
        foreach ($ownedProcess in $ownedProcesses) {
            Stop-PackageOwnedNodeProcess $ownedProcess
        }
    }
    Start-Sleep -Milliseconds 100
} while ([DateTime]::UtcNow -lt $deadline)

throw 'Package-owned Max Ultra MCP processes keep restarting. Close ChatGPT Desktop, Codex, and Claude Code, then try again.'
