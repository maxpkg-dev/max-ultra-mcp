# Stops only a process tree proven to belong to a Max-launched Max Ultra MCP server.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OwnershipFile,

    [Parameter(Mandatory = $true)]
    [int]$Port,

    [string]$OwnerToken = '',

    [int]$ClosingMaxPid = 0,

    [int]$MaxProcessCountOverride = -1
)

$ErrorActionPreference = 'Stop'

function Write-HelperStatus([string]$Level, [string]$Message) {
    [Console]::Error.WriteLine("[3DGROUND | Max Ultra MCP] $Level | $Message")
}

function Get-ProcessRecord([int]$ProcessId) {
    if ($ProcessId -le 0) {
        return $null
    }
    return Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

function Test-SamePath([string]$ActualPath, [string]$ExpectedPath) {
    if ([string]::IsNullOrWhiteSpace($ActualPath) -or [string]::IsNullOrWhiteSpace($ExpectedPath)) {
        return $false
    }
    try {
        $actualFullPath = [IO.Path]::GetFullPath($ActualPath)
        $expectedFullPath = [IO.Path]::GetFullPath($ExpectedPath)
        return [string]::Equals($actualFullPath, $expectedFullPath, [StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Test-CreationTime([object]$ProcessRecord, [string]$ExpectedUtc, [double]$ToleranceSeconds) {
    if ($null -eq $ProcessRecord -or [string]::IsNullOrWhiteSpace($ExpectedUtc)) {
        return $false
    }
    try {
        $actualUtc = ([DateTime]$ProcessRecord.CreationDate).ToUniversalTime()
        $expected = [DateTime]::Parse($ExpectedUtc).ToUniversalTime()
        return [Math]::Abs(($actualUtc - $expected).TotalSeconds) -le $ToleranceSeconds
    }
    catch {
        return $false
    }
}

function Test-CommandLineContains([object]$ProcessRecord, [string]$RequiredText) {
    if ($null -eq $ProcessRecord -or [string]::IsNullOrWhiteSpace([string]$ProcessRecord.CommandLine) -or
        [string]::IsNullOrWhiteSpace($RequiredText)) {
        return $false
    }
    return ([string]$ProcessRecord.CommandLine).IndexOf($RequiredText, [StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Read-Ownership([string]$CandidatePath) {
    try {
        if (-not (Test-Path -LiteralPath $CandidatePath -PathType Leaf)) {
            return $null
        }
        return Get-Content -LiteralPath $CandidatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

try {
    if ($MaxProcessCountOverride -ge 0) {
        $liveMaxProcesses = @()
        $liveMaxCount = $MaxProcessCountOverride
    }
    else {
        $liveMaxProcesses = @(Get-Process -Name 3dsmax -ErrorAction SilentlyContinue |
            Where-Object { -not $_.HasExited })
        $liveMaxCount = $liveMaxProcesses.Count
    }
    if ($liveMaxCount -ne 1) {
        Write-HelperStatus 'SKIPPED' "Found $liveMaxCount live 3ds Max processes; the owned server was left running."
        exit 0
    }
    if ($MaxProcessCountOverride -lt 0 -and $ClosingMaxPid -gt 0 -and
        $liveMaxProcesses[0].Id -ne $ClosingMaxPid) {
        Write-HelperStatus 'SKIPPED' 'The sole live 3ds Max process is not the Max process that launched this helper.'
        exit 0
    }

    $resolvedOwnershipFile = [IO.Path]::GetFullPath($OwnershipFile)
    $ownershipDirectory = Split-Path -Parent $resolvedOwnershipFile
    $ownership = $null
    $selectedOwnershipFile = $resolvedOwnershipFile
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ($null -eq $ownership -and [DateTime]::UtcNow -lt $deadline) {
        $ownership = Read-Ownership $resolvedOwnershipFile
        if ($null -eq $ownership -and -not [string]::IsNullOrWhiteSpace($OwnerToken) -and
            (Test-Path -LiteralPath $ownershipDirectory -PathType Container)) {
            foreach ($candidate in Get-ChildItem -LiteralPath $ownershipDirectory -Filter 'max-ultra-mcp-owned-*.json' -File -ErrorAction SilentlyContinue) {
                $candidateOwnership = Read-Ownership $candidate.FullName
                if ($null -ne $candidateOwnership -and
                    [string]::Equals([string]$candidateOwnership.ownerToken, $OwnerToken, [StringComparison]::Ordinal)) {
                    $ownership = $candidateOwnership
                    $selectedOwnershipFile = $candidate.FullName
                    break
                }
            }
        }
        if ($null -eq $ownership) {
            Start-Sleep -Milliseconds 100
        }
    }
    if ($null -eq $ownership) {
        Write-HelperStatus 'SKIPPED' 'No Max-launched ownership record was found; manual or pre-existing servers were left running.'
        exit 0
    }

    $expectedProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $expectedScriptPath = [IO.Path]::GetFullPath((Join-Path $expectedProjectRoot 'core\server.js'))
    $expectedLauncherPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'start-server.bat'))
    $requiredToken = [string]$ownership.ownerToken
    $ownedNodePid = [int]$ownership.pid
    $ownedLauncherPid = [int]$ownership.launcherPid

    $invocationMatches = [int]$ownership.port -eq $Port -or
        (-not [string]::IsNullOrWhiteSpace($OwnerToken) -and
            [string]::Equals($requiredToken, $OwnerToken, [StringComparison]::Ordinal))
    if ([int]$ownership.schemaVersion -ne 1 -or [string]$ownership.server -ne 'max-ultra-mcp' -or
        -not $invocationMatches -or [string]::IsNullOrWhiteSpace($requiredToken) -or
        -not (Test-SamePath ([string]$ownership.ownerFile) $selectedOwnershipFile) -or
        -not (Test-SamePath ([string]$ownership.projectRoot) $expectedProjectRoot) -or
        -not (Test-SamePath ([string]$ownership.scriptPath) $expectedScriptPath) -or
        -not (Test-SamePath ([string]$ownership.launcherPath) $expectedLauncherPath)) {
        throw 'Ownership record does not match this project, endpoint, or helper invocation.'
    }

    $nodeProcess = Get-ProcessRecord $ownedNodePid
    if ($null -eq $nodeProcess) {
        Remove-Item -LiteralPath $selectedOwnershipFile -Force -ErrorAction SilentlyContinue
        Write-HelperStatus 'SKIPPED' 'The recorded Max Ultra MCP server process has already exited.'
        exit 0
    }
    if ([string]$nodeProcess.Name -ne 'node.exe' -or
        -not (Test-CreationTime $nodeProcess ([string]$ownership.processStartedAtUtc) 10) -or
        -not (Test-CommandLineContains $nodeProcess $expectedScriptPath)) {
        throw 'Recorded server PID is not the exact Max Ultra MCP Node.js process.'
    }

    $launcherProcess = Get-ProcessRecord $ownedLauncherPid
    if ($null -eq $launcherProcess -or [string]$launcherProcess.Name -ne 'cmd.exe' -or
        -not (Test-CreationTime $launcherProcess ([string]$ownership.launcherStartedAtUtc) 2) -or
        -not (Test-CommandLineContains $launcherProcess $expectedLauncherPath) -or
        -not (Test-CommandLineContains $launcherProcess $selectedOwnershipFile) -or
        -not (Test-CommandLineContains $launcherProcess $requiredToken) -or
        -not (Test-CommandLineContains $launcherProcess '--no-pause')) {
        throw 'Recorded BAT launcher PID is not the exact Max Ultra MCP launcher process.'
    }

    Stop-Process -Id $ownedNodePid -Force -ErrorAction Stop
    $nodeDeadline = [DateTime]::UtcNow.AddSeconds(5)
    while ($null -ne (Get-ProcessRecord $ownedNodePid) -and [DateTime]::UtcNow -lt $nodeDeadline) {
        Start-Sleep -Milliseconds 100
    }
    if ($null -ne (Get-ProcessRecord $ownedNodePid)) {
        throw 'The verified Max Ultra MCP Node.js process did not exit within five seconds.'
    }

    $launcherDeadline = [DateTime]::UtcNow.AddSeconds(5)
    while ($null -ne (Get-ProcessRecord $ownedLauncherPid) -and [DateTime]::UtcNow -lt $launcherDeadline) {
        Start-Sleep -Milliseconds 100
    }
    $remainingLauncher = Get-ProcessRecord $ownedLauncherPid
    if ($null -ne $remainingLauncher) {
        if ([string]$remainingLauncher.Name -ne 'cmd.exe' -or
            -not (Test-CreationTime $remainingLauncher ([string]$ownership.launcherStartedAtUtc) 2) -or
            -not (Test-CommandLineContains $remainingLauncher $expectedLauncherPath) -or
            -not (Test-CommandLineContains $remainingLauncher $requiredToken)) {
            throw 'BAT launcher identity changed before bounded fallback termination.'
        }
        Stop-Process -Id $ownedLauncherPid -Force -ErrorAction Stop
    }

    $currentOwnership = Read-Ownership $selectedOwnershipFile
    if ($null -ne $currentOwnership -and [int]$currentOwnership.pid -eq $ownedNodePid -and
        [string]::Equals([string]$currentOwnership.ownerToken, $requiredToken, [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $selectedOwnershipFile -Force -ErrorAction SilentlyContinue
    }
    Write-HelperStatus 'STOPPED' "Terminated verified Max Ultra MCP server PID $ownedNodePid and released its BAT launcher."
    exit 0
}
catch {
    Write-HelperStatus 'REFUSED' "$($_.Exception.Message) No unverified process was terminated."
    exit 3
}