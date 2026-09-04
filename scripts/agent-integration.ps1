# Checks and installs Max Ultra MCP registrations for supported local AI clients.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

param(
    [ValidateSet('Status','Install')][string]$Action = 'Status',
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [ValidateSet('core','archviz','full')][string]$Profile = 'archviz',
    [switch]$InstallOpenAI,
    [switch]$InstallClaudeCode
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$serverName = 'max-ultra-mcp'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$serverPath = Join-Path $projectRoot 'core\server.js'
$statusCheckDeadlineUtc = [DateTime]::UtcNow.AddSeconds(30)
$clientCommandTimeoutMilliseconds = 10000
$nodeProbeTimeoutMilliseconds = 5000
$installDeadlineUtc = [DateTime]::UtcNow.AddSeconds(90)

function ConvertTo-IniValue([object]$Value) {
    if ($null -eq $Value) { return '' }
    return ($Value.ToString() -replace '[\r\n]+', ' ').Trim()
}

function Write-IntegrationResult([hashtable]$Sections) {
    $resolvedResultPath = [IO.Path]::GetFullPath($ResultPath)
    $resultDirectory = Split-Path -Parent $resolvedResultPath
    if ([string]::IsNullOrWhiteSpace($resultDirectory)) { throw 'ResultPath must include a parent directory.' }
    New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
    $temporaryPath = $resolvedResultPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($sectionName in $Sections.Keys) {
        $lines.Add("[$sectionName]")
        foreach ($key in $Sections[$sectionName].Keys) {
            $lines.Add("$key=$(ConvertTo-IniValue $Sections[$sectionName][$key])")
        }
        $lines.Add('')
    }
    [IO.File]::WriteAllLines($temporaryPath, $lines.ToArray(), (New-Object Text.UTF8Encoding($true)))
    Move-Item -LiteralPath $temporaryPath -Destination $resolvedResultPath -Force
}

function ConvertTo-ProcessArgument([string]$ArgumentValue) {
    if ($null -eq $ArgumentValue -or $ArgumentValue.Length -eq 0) { return '""' }
    if ($ArgumentValue -notmatch '[\s"]') { return $ArgumentValue }

    $quotedArgument = New-Object Text.StringBuilder
    [void]$quotedArgument.Append('"')
    $backslashCount = 0
    foreach ($argumentCharacter in $ArgumentValue.ToCharArray()) {
        if ($argumentCharacter -eq [char]'\') {
            $backslashCount++
            continue
        }
        if ($argumentCharacter -eq [char]'"') {
            if ($backslashCount -gt 0) { [void]$quotedArgument.Append([char]'\', ($backslashCount * 2)) }
            [void]$quotedArgument.Append('\"')
            $backslashCount = 0
            continue
        }
        if ($backslashCount -gt 0) {
            [void]$quotedArgument.Append([char]'\', $backslashCount)
            $backslashCount = 0
        }
        [void]$quotedArgument.Append($argumentCharacter)
    }
    if ($backslashCount -gt 0) { [void]$quotedArgument.Append([char]'\', ($backslashCount * 2)) }
    [void]$quotedArgument.Append('"')
    return $quotedArgument.ToString()
}

function Get-RemainingTimeoutMilliseconds([DateTime]$DeadlineUtc, [int]$MaximumWaitMilliseconds) {
    $remainingMilliseconds = [Math]::Floor(($DeadlineUtc - [DateTime]::UtcNow).TotalMilliseconds)
    if ($remainingMilliseconds -le 0) { return 0 }
    return [int][Math]::Min($remainingMilliseconds, $MaximumWaitMilliseconds)
}

function Stop-ExternalCommandProcess([Diagnostics.Process]$CommandProcess) {
    if ($null -eq $CommandProcess) { return }
    try { if ($CommandProcess.HasExited) { return } } catch { return }

    try {
        $taskKillPath = Join-Path $env:SystemRoot 'System32\taskkill.exe'
        if (Test-Path -LiteralPath $taskKillPath -PathType Leaf) {
            $stopInfo = New-Object Diagnostics.ProcessStartInfo
            $stopInfo.FileName = $taskKillPath
            $stopInfo.Arguments = "/PID $($CommandProcess.Id) /T /F"
            $stopInfo.UseShellExecute = $false
            $stopInfo.CreateNoWindow = $true
            $stopInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
            $stopInfo.RedirectStandardOutput = $true
            $stopInfo.RedirectStandardError = $true
            $stopProcess = [Diagnostics.Process]::Start($stopInfo)
            if ($null -ne $stopProcess) {
                [void]$stopProcess.WaitForExit(3000)
                $stopProcess.Dispose()
            }
        }
    } catch {}

    try { if (-not $CommandProcess.HasExited) { $CommandProcess.Kill() } } catch {}
    try { [void]$CommandProcess.WaitForExit(2000) } catch {}
}

function Invoke-ExternalCommand([string]$CommandPath, [string[]]$Arguments, [DateTime]$DeadlineUtc, [int]$MaximumWaitMilliseconds) {
    $waitMilliseconds = Get-RemainingTimeoutMilliseconds $DeadlineUtc $MaximumWaitMilliseconds
    if ($waitMilliseconds -le 0) {
        return @{ ExitCode = -1; Output = ''; TimedOut = $true; InvocationFailed = $false }
    }

    $commandProcess = $null
    try {
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $commandExtension = [IO.Path]::GetExtension($CommandPath).ToLowerInvariant()
        if ($commandExtension -eq '.cmd' -or $commandExtension -eq '.bat') {
            $startInfo.FileName = if ([string]::IsNullOrWhiteSpace($env:ComSpec)) { 'cmd.exe' } else { $env:ComSpec }
            $commandLine = @((ConvertTo-ProcessArgument $CommandPath)) + @($Arguments | ForEach-Object { ConvertTo-ProcessArgument $_ })
            $startInfo.Arguments = '/d /s /c call ' + ($commandLine -join ' ')
        } else {
            $startInfo.FileName = $CommandPath
            $startInfo.Arguments = (@($Arguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join ' ')
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        $commandProcess = New-Object Diagnostics.Process
        $commandProcess.StartInfo = $startInfo
        if (-not $commandProcess.Start()) {
            return @{ ExitCode = -1; Output = ''; TimedOut = $false; InvocationFailed = $true }
        }
        $standardOutputTask = $commandProcess.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $commandProcess.StandardError.ReadToEndAsync()
        if (-not $commandProcess.WaitForExit($waitMilliseconds)) {
            Stop-ExternalCommandProcess $commandProcess
            return @{ ExitCode = -1; Output = ''; TimedOut = $true; InvocationFailed = $false }
        }
        $commandProcess.WaitForExit()
        $outputParts = New-Object System.Collections.Generic.List[string]
        if ($standardOutputTask.IsCompleted -and -not [string]::IsNullOrWhiteSpace($standardOutputTask.Result)) { $outputParts.Add($standardOutputTask.Result) }
        if ($standardErrorTask.IsCompleted -and -not [string]::IsNullOrWhiteSpace($standardErrorTask.Result)) { $outputParts.Add($standardErrorTask.Result) }
        $outputText = (($outputParts.ToArray() -join ' ') -replace '[\r\n]+', ' ').Trim()
        if ($outputText.Length -gt 65536) { $outputText = $outputText.Substring(0, 65536) }
        return @{ ExitCode = $commandProcess.ExitCode; Output = $outputText; TimedOut = $false; InvocationFailed = $false }
    } catch {
        Stop-ExternalCommandProcess $commandProcess
        return @{ ExitCode = -1; Output = ''; TimedOut = $false; InvocationFailed = $true }
    } finally {
        if ($null -ne $commandProcess) { try { $commandProcess.Dispose() } catch {} }
    }
}

function Resolve-NodeRuntime([DateTime]$DeadlineUtc) {
    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add((Join-Path $projectRoot 'runtime\win-x64\node.exe'))
    $nodeCommand = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($nodeCommand) { $candidates.Add($nodeCommand.Source) }
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $candidates.Add((Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $codexRuntimeRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node'
        if (Test-Path -LiteralPath $codexRuntimeRoot -PathType Container) {
            Get-ChildItem -LiteralPath $codexRuntimeRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | ForEach-Object {
                $candidates.Add((Join-Path $_.FullName 'bin\node.exe'))
            }
        }
    }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        try {
            $versionProbe = Invoke-ExternalCommand $candidate @('-p','process.versions.node') $DeadlineUtc $nodeProbeTimeoutMilliseconds
            if ($versionProbe.TimedOut) { break }
            if (-not $versionProbe.InvocationFailed -and $versionProbe.ExitCode -eq 0) {
                $versionText = ($versionProbe.Output -split '\s+' | Select-Object -First 1)
                if ([Version]$versionText -ge [Version]'22.0.0') { return $candidate }
            }
        } catch {}
    }
    return $null
}

function Resolve-ClientCommandPath([string]$ClientId, [string]$ExecutableName) {
    $command = Get-Command $ExecutableName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source) { return $command.Source }

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($ClientId -eq 'openai' -and -not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $codexBinRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
        if (Test-Path -LiteralPath $codexBinRoot -PathType Container) {
            Get-ChildItem -LiteralPath $codexBinRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | ForEach-Object {
                $candidates.Add((Join-Path $_.FullName 'codex.exe'))
            }
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
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    return $null
}

function Test-StdioHostRestartRequired {
    if (-not (Test-Path -LiteralPath $serverPath -PathType Leaf)) { return $false }
    try {
        $serverWriteTimeUtc = (Get-Item -LiteralPath $serverPath).LastWriteTimeUtc
        $stdioProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                $commandLine = [string]$_.CommandLine
                -not [string]::IsNullOrWhiteSpace($commandLine) -and
                    $commandLine.IndexOf($serverPath, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                    $commandLine.IndexOf('--stdio', [StringComparison]::OrdinalIgnoreCase) -ge 0
            })
        return @($stdioProcesses | Where-Object { ([DateTime]$_.CreationDate).ToUniversalTime() -lt $serverWriteTimeUtc.AddSeconds(-2) }).Count -gt 0
    }
    catch { return $false }
}

function New-ClientCheckFailedStatus([string]$ClientId, [string]$DisplayName, [string]$CommandPath, [bool]$TimedOut) {
    return @{
        Id = $ClientId
        DisplayName = $DisplayName
        CommandPath = $CommandPath
        CliAvailable = $true
        Configured = $false
        State = 'check_failed'
        Detail = if ($TimedOut) { "$DisplayName status check timed out." } else { "$DisplayName status check failed. Refresh status to retry." }
    }
}

function Get-ClientStatus([string]$ClientId, [string]$DisplayName, [string]$ExecutableName, [DateTime]$DeadlineUtc) {
    $commandPath = Resolve-ClientCommandPath $ClientId $ExecutableName
    if ([string]::IsNullOrWhiteSpace($commandPath)) {
        $configuredWithoutCli = $false
        $restartRequired = $false
        if ($ClientId -eq 'openai' -and -not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
            $codexConfigPath = Join-Path $env:USERPROFILE '.codex\config.toml'
            if (Test-Path -LiteralPath $codexConfigPath -PathType Leaf) {
                try {
                    $configuredWithoutCli = [bool](Select-String -LiteralPath $codexConfigPath -Pattern '^\s*\[mcp_servers\.(?:"max-ultra-mcp"|max-ultra-mcp)\]\s*$' -Quiet)
                } catch {}
            }
            $restartRequired = $configuredWithoutCli -and (Test-StdioHostRestartRequired)
        }
        return @{
            Id = $ClientId
            DisplayName = $DisplayName
            CommandPath = ''
            CliAvailable = $false
            Configured = $configuredWithoutCli
            State = if ($restartRequired) { 'restart_required' } elseif ($configuredWithoutCli) { 'configured' } else { 'cli_missing' }
            Detail = if ($restartRequired) { "$DisplayName must be restarted or reconnected to reload the MCP host." } elseif ($configuredWithoutCli) { "$DisplayName is configured." } else { "$DisplayName CLI was not found. Use the manual STDIO values shown in 3ds Max." }
        }
    }

    $probe = Invoke-ExternalCommand $commandPath @('mcp','get',$serverName) $DeadlineUtc $clientCommandTimeoutMilliseconds
    if ($probe.TimedOut -or $probe.InvocationFailed) {
        return New-ClientCheckFailedStatus $ClientId $DisplayName $commandPath $probe.TimedOut
    }
    $configured = $probe.ExitCode -eq 0
    if (-not $configured) {
        $listProbe = Invoke-ExternalCommand $commandPath @('mcp','list') $DeadlineUtc $clientCommandTimeoutMilliseconds
        if ($listProbe.TimedOut -or $listProbe.InvocationFailed -or $listProbe.ExitCode -ne 0) {
            return New-ClientCheckFailedStatus $ClientId $DisplayName $commandPath $listProbe.TimedOut
        }
        $configured = $listProbe.Output -match '(?im)^\s*max-ultra-mcp(?:\s|$)'
    }
    $restartRequired = $configured -and (Test-StdioHostRestartRequired)
    return @{
        Id = $ClientId
        DisplayName = $DisplayName
        CommandPath = $commandPath
        CliAvailable = $true
        Configured = $configured
        State = if ($restartRequired) { 'restart_required' } elseif ($configured) { 'configured' } else { 'not_configured' }
        Detail = if ($restartRequired) { "$DisplayName must be restarted or reconnected to reload the MCP host." } elseif ($configured) { "$DisplayName is configured." } else { "$DisplayName is ready for setup." }
    }
}

function Install-OpenAIClient([hashtable]$Status, [string]$NodePath, [DateTime]$DeadlineUtc) {
    if (-not $Status.CliAvailable) { return $Status }
    if ([string]::IsNullOrWhiteSpace($NodePath) -or -not (Test-Path -LiteralPath $serverPath -PathType Leaf)) {
        $Status.State = 'runtime_missing'
        $Status.Configured = $false
        $Status.Detail = 'The MCP runtime or core/server.js is missing from this package.'
        return $Status
    }
    Invoke-ExternalCommand $Status.CommandPath @('mcp','remove',$serverName) $DeadlineUtc $clientCommandTimeoutMilliseconds | Out-Null
    $install = Invoke-ExternalCommand $Status.CommandPath @('mcp','add',$serverName,'--env',"MAX_ULTRA_MCP_TOOL_PROFILE=$Profile",'--',$NodePath,$serverPath,'--stdio') $DeadlineUtc $clientCommandTimeoutMilliseconds
    $Status.Configured = -not $install.TimedOut -and -not $install.InvocationFailed -and $install.ExitCode -eq 0
    $Status.State = if ($Status.Configured) { 'configured' } else { 'install_failed' }
    $Status.Detail = if ($Status.Configured) { 'ChatGPT Desktop / Codex integration was installed.' } else { 'Installation failed. Run the client CLI manually for diagnostic output.' }
    return $Status
}

function Install-ClaudeCodeClient([hashtable]$Status, [string]$NodePath, [DateTime]$DeadlineUtc) {
    if (-not $Status.CliAvailable) { return $Status }
    if ([string]::IsNullOrWhiteSpace($NodePath) -or -not (Test-Path -LiteralPath $serverPath -PathType Leaf)) {
        $Status.State = 'runtime_missing'
        $Status.Configured = $false
        $Status.Detail = 'The MCP runtime or core/server.js is missing from this package.'
        return $Status
    }
    Invoke-ExternalCommand $Status.CommandPath @('mcp','remove',$serverName,'--scope','user') $DeadlineUtc $clientCommandTimeoutMilliseconds | Out-Null
    $install = Invoke-ExternalCommand $Status.CommandPath @('mcp','add',$serverName,'--scope','user','--env',"MAX_ULTRA_MCP_TOOL_PROFILE=$Profile",'--',$NodePath,$serverPath,'--stdio') $DeadlineUtc $clientCommandTimeoutMilliseconds
    $Status.Configured = -not $install.TimedOut -and -not $install.InvocationFailed -and $install.ExitCode -eq 0
    $Status.State = if ($Status.Configured) { 'configured' } else { 'install_failed' }
    $Status.Detail = if ($Status.Configured) { 'Claude Code integration was installed for the current Windows user.' } else { 'Installation failed. Run the client CLI manually for diagnostic output.' }
    return $Status
}

try {
    $nodePath = Resolve-NodeRuntime $statusCheckDeadlineUtc
    $openAI = Get-ClientStatus 'openai' 'ChatGPT Desktop / Codex' 'codex' $statusCheckDeadlineUtc
    $claudeCode = Get-ClientStatus 'claudeCode' 'Claude Code' 'claude' $statusCheckDeadlineUtc

    if ($Action -eq 'Install') {
        if ($InstallOpenAI) { $openAI = Install-OpenAIClient $openAI $nodePath $installDeadlineUtc }
        if ($InstallClaudeCode) { $claudeCode = Install-ClaudeCodeClient $claudeCode $nodePath $installDeadlineUtc }
    }

    $runtimeReady = -not [string]::IsNullOrWhiteSpace($nodePath) -and (Test-Path -LiteralPath $serverPath -PathType Leaf)
    $message = if ($Action -eq 'Install') { 'Selected integrations were processed. Restart or reconnect the configured AI clients.' } else { 'Integration status was refreshed.' }
    Write-IntegrationResult ([ordered]@{
        operation = [ordered]@{ state = 'complete'; action = $Action.ToLowerInvariant(); message = $message }
        openai = [ordered]@{ cliAvailable = $openAI.CliAvailable.ToString().ToLowerInvariant(); configured = $openAI.Configured.ToString().ToLowerInvariant(); state = $openAI.State; detail = $openAI.Detail }
        claudeCode = [ordered]@{ cliAvailable = $claudeCode.CliAvailable.ToString().ToLowerInvariant(); configured = $claudeCode.Configured.ToString().ToLowerInvariant(); state = $claudeCode.State; detail = $claudeCode.Detail }
        runtime = [ordered]@{ ready = $runtimeReady.ToString().ToLowerInvariant(); command = $nodePath; server = $serverPath; arguments = '"' + $serverPath + '" --stdio'; environment = "MAX_ULTRA_MCP_TOOL_PROFILE=$Profile" }
    })
    exit 0
} catch {
    try {
        Write-IntegrationResult ([ordered]@{
            operation = [ordered]@{ state = 'failed'; action = $Action.ToLowerInvariant(); message = $_.Exception.Message }
        })
    } catch {}
    exit 1
}
