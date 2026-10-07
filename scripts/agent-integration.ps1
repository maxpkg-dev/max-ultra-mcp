# Checks and installs Max Ultra MCP registrations for supported local AI clients.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

param(
    [ValidateSet('Status','Install','InstallCli')][string]$Action = 'Status',
    [Parameter(Mandatory = $true)][string]$ResultPath,
    [ValidateSet('core','archviz','full')][string]$Profile = 'archviz',
    [ValidateRange(1,65535)][int]$Port = 47635,
    [switch]$InstallOpenAI,
    [switch]$InstallClaudeCode,
    [switch]$InstallAntigravity,
    [switch]$ConfirmCliInstall
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
# Max can remain open across a client installation; incorporate current persisted PATH in this helper only.
$env:PATH = $env:PATH + ';' + [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
$serverName = 'max-ultra-mcp'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$serverPath = Join-Path $projectRoot 'core\server.js'
$statusCheckDeadlineUtc = [DateTime]::UtcNow.AddSeconds(15)
$clientCommandTimeoutMilliseconds = 10000
$nodeProbeTimeoutMilliseconds = 5000
$installDeadlineUtc = [DateTime]::UtcNow.AddSeconds(90)
$script:integrationCancelPath = if ($Action -eq 'InstallCli') { $ResultPath + '.cancel' } else { '' }
. (Join-Path $PSScriptRoot 'antigravity-integration.ps1')

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
    $cancelVariable = Get-Variable integrationCancelPath -Scope Script -ErrorAction SilentlyContinue
    if ($cancelVariable -and $cancelVariable.Value -and (Test-Path -LiteralPath $cancelVariable.Value)) {
        return @{ ExitCode = -1; Output = ''; TimedOut = $false; InvocationFailed = $false; Cancelled = $true }
    }
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
        } elseif ($commandExtension -eq '.ps1') {
            $startInfo.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $startInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + (ConvertTo-ProcessArgument $CommandPath) + ' ' + (@($Arguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join ' ')
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
        $commandDeadline = [DateTime]::UtcNow.AddMilliseconds($waitMilliseconds)
        while (-not $commandProcess.WaitForExit(200)) {
            $cancelVariable = Get-Variable integrationCancelPath -Scope Script -ErrorAction SilentlyContinue
            if ($cancelVariable -and $cancelVariable.Value -and (Test-Path -LiteralPath $cancelVariable.Value)) {
                Stop-ExternalCommandProcess $commandProcess
                return @{ ExitCode = -1; Output = ''; TimedOut = $false; InvocationFailed = $false; Cancelled = $true }
            }
            if ([DateTime]::UtcNow -ge $commandDeadline) {
                Stop-ExternalCommandProcess $commandProcess
                return @{ ExitCode = -1; Output = ''; TimedOut = $true; InvocationFailed = $false }
            }
        }
        # Process exit does not guarantee ReadToEndAsync has completed.
        $drainTimeout = Get-RemainingTimeoutMilliseconds $DeadlineUtc $MaximumWaitMilliseconds
        if ($drainTimeout -le 0 -or -not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($standardOutputTask, $standardErrorTask), $drainTimeout)) {
            return @{ ExitCode = -1; Output = ''; TimedOut = $true; InvocationFailed = $false }
        }
        $outputParts = New-Object System.Collections.Generic.List[string]
        if ($standardOutputTask.IsCompleted -and -not [string]::IsNullOrWhiteSpace($standardOutputTask.Result)) { $outputParts.Add($standardOutputTask.Result) }
        if ($standardErrorTask.IsCompleted -and -not [string]::IsNullOrWhiteSpace($standardErrorTask.Result)) { $outputParts.Add($standardErrorTask.Result) }
        $outputText = ($outputParts.ToArray() -join "`n").Trim()
        if ($outputText.Length -gt 65536) { $outputText = $outputText.Substring(0, 65536) }
        return @{ ExitCode = $commandProcess.ExitCode; Output = $outputText; StandardOutput = $standardOutputTask.Result; TimedOut = $false; InvocationFailed = $false }
    } catch {
        Stop-ExternalCommandProcess $commandProcess
        $nativeError = $_.Exception
        while ($null -ne $nativeError.InnerException) { $nativeError = $nativeError.InnerException }
        $nativeErrorCode = if ($nativeError -is [ComponentModel.Win32Exception]) { $nativeError.NativeErrorCode } else { 0 }
        return @{ ExitCode = -1; Output = ''; TimedOut = $false; InvocationFailed = $true; NativeErrorCode = $nativeErrorCode }
    } finally {
        if ($null -ne $commandProcess) { try { $commandProcess.Dispose() } catch {} }
    }
}

function Test-NodeRuntimeCandidate([string]$CandidatePath, [DateTime]$DeadlineUtc) {
    $probeResult = @{ State = 'runtime_missing'; Command = ''; Candidate = $CandidatePath; Detail = 'Node.js file is missing: ' + $CandidatePath }
    if (-not (Test-Path -LiteralPath $CandidatePath -PathType Leaf)) { return $probeResult }
    $probe = Invoke-ExternalCommand $CandidatePath @('-p','process.versions.node') $DeadlineUtc $nodeProbeTimeoutMilliseconds
    if ($probe.TimedOut) {
        $probeResult.State = 'runtime_timeout'
        $probeResult.Detail = 'Node.js check timed out. Refresh status to retry. Checked: ' + $CandidatePath
    } elseif ($probe.InvocationFailed -or $probe.ExitCode -ne 0) {
        $probeResult.State = 'runtime_launch_failed'
        $probeResult.Detail = 'Node.js exists but its version check failed (exit ' + $probe.ExitCode + '). Checked: ' + $CandidatePath
        if ($probe.ContainsKey('NativeErrorCode') -and $probe.NativeErrorCode -ne 0) {
            $probeResult.Detail = 'Windows could not launch Node.js (error ' + $probe.NativeErrorCode + '). Checked: ' + $CandidatePath
        }
    } else {
        $versionText = $probe.StandardOutput.Trim()
        $parsedVersion = $null
        if ($versionText -notmatch '^\d+\.\d+\.\d+$' -or -not [Version]::TryParse($versionText, [ref]$parsedVersion)) {
            $probeResult.State = 'runtime_invalid_response'
            $probeResult.Detail = 'Node.js returned an unreadable version. Checked: ' + $CandidatePath
        } elseif ($parsedVersion.Major -lt 22) {
            $probeResult.State = 'runtime_unsupported'
            $probeResult.Detail = 'Node.js ' + $versionText + ' is unsupported; version 22 or newer is required. Checked: ' + $CandidatePath
        } else {
            $probeResult.State = 'ready'
            $probeResult.Command = $CandidatePath
            $probeResult.Detail = 'Node.js ' + $versionText + ' verified. Checked: ' + $CandidatePath
        }
    }
    return $probeResult
}

function Resolve-NodeRuntime([DateTime]$DeadlineUtc) {
    if (-not (Test-Path -LiteralPath $serverPath -PathType Leaf)) {
        return @{ State = 'runtime_missing'; Command = ''; Candidate = $serverPath; Detail = 'Package file is missing: ' + $serverPath + '. Reinstall Max Ultra MCP.' }
    }
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
    $firstFailure = $null
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $candidateResult = Test-NodeRuntimeCandidate $candidate $DeadlineUtc
        if ($candidateResult.State -eq 'ready') { return $candidateResult }
        if ($null -eq $firstFailure) { $firstFailure = $candidateResult }
        if ((Get-RemainingTimeoutMilliseconds $DeadlineUtc 1) -eq 0) { break }
    }
    if ($null -ne $firstFailure) { return $firstFailure }
    return @{ State = 'runtime_missing'; Command = ''; Candidate = $candidates[0]; Detail = 'Node.js file is missing: ' + $candidates[0] + '. Reinstall Max Ultra MCP.' }
}

function Get-DesktopClientStatus([string]$ClientId) {
    # Read installation evidence only. A CLI, saved configuration, or account is not a desktop app.
    $desktop = @{ Available = $false; State = 'missing'; Detail = 'Desktop app not found.' }
    if ($ClientId -eq 'antigravity') {
        $status = Get-AntigravityStatus
        $desktop.Available = $status.installed -eq 'true'
        $desktop.State = if ($desktop.Available) { 'installed' } else { 'missing' }
        return $desktop
    }
    if ($ClientId -notin @('openai','claudeCode')) { throw 'Unsupported desktop client.' }
    $relativePaths = if ($ClientId -eq 'openai') { @('Programs\Codex\Codex.exe', 'Programs\ChatGPT\ChatGPT.exe') } else { @('AnthropicClaude\claude.exe', 'Programs\Claude\Claude.exe') }
    if ($env:LOCALAPPDATA) {
        foreach ($relativePath in $relativePaths) {
            if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA $relativePath) -PathType Leaf) {
                $desktop.Available = $true; $desktop.State = 'installed'; $desktop.Detail = 'Desktop app found. Sign-in and local tool access are not verified.'
                return $desktop
            }
        }
    }
    # Current official Windows package identities. Do not mistake the older Chat-only app for Codex.
    $packageName = if ($ClientId -eq 'openai') { 'OpenAI.Codex' } else { 'Claude' }
    try {
        $packages = @(Get-AppxPackage -Name $packageName -ErrorAction Stop)
        if ($packages.Count -gt 0) {
            if (@($packages | Where-Object { [string]$_.Status -eq 'Ok' -and -not $_.IsFramework }).Count -gt 0) {
                $desktop.Available = $true; $desktop.State = 'installed'; $desktop.Detail = 'Desktop app registered for this Windows user. Sign-in and local tool access are not verified.'
            } else {
                $desktop.State = 'check_failed'; $desktop.Detail = 'Desktop app is registered but Windows reports a package problem. Repair or update it through the official installer, then refresh.'
            }
        }
    } catch {
        $desktop.State = 'check_failed'
        $desktop.Detail = 'Windows desktop-app discovery failed. Refresh status or use the official desktop installation instructions; a failed check does not prove the app is missing.'
    }
    return $desktop
}

function Add-DesktopClientStatus([hashtable]$Status, $Desktop = $null) {
    if ($null -eq $Desktop) { $Desktop = Get-DesktopClientStatus $Status.Id }
    $desktop = $Desktop
    $Status.DesktopAvailable = $desktop.Available
    $Status.DesktopState = $desktop.State
    $Status.DesktopDetail = $desktop.Detail
    $Status.DesktopInstallUrl = if ($Status.Id -eq 'openai') { 'https://chatgpt.com/features/desktop/' } else { 'https://claude.com/download' }
    $Status.DesktopInstructions = if ($Status.Id -eq 'openai') {
        'Open the ChatGPT / Codex desktop app from Start, sign in, and use Codex mode on this Windows computer. Run Test prompt there. The CLI is only used by automatic MCP setup; terminal chat is not required.'
    } else {
        'Open Claude from Start, sign in, choose the Code tab and a Local session on this Windows computer, then run Test prompt. Code access requires an eligible account or plan. This setup targets the Code tab, not ordinary Chat, Cowork, Cloud, or WSL. The CLI is only used by automatic MCP setup; terminal chat is not required.'
    }
    return $Status
}

function ConvertTo-ClientResult([hashtable]$Status) {
    return [ordered]@{
        cliAvailable = $Status.CliAvailable.ToString().ToLowerInvariant(); configured = $Status.Configured.ToString().ToLowerInvariant()
        state = $Status.State; detail = $Status.Detail
        detailKind = if ($Status.ContainsKey('DetailKind')) { $Status.DetailKind } else { '' }
        desktopAvailable = $Status.DesktopAvailable.ToString().ToLowerInvariant(); desktopState = $Status.DesktopState
        desktopDetail = $Status.DesktopDetail; desktopInstallUrl = $Status.DesktopInstallUrl; desktopInstructions = $Status.DesktopInstructions
    }
}

function Resolve-ClientCommandPath([string]$ClientId, [string]$ExecutableName) {
    $command = Get-Command $ExecutableName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source) { return $command.Source }

    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $candidates.Add((Join-Path $env:USERPROFILE ('.local\bin\' + $ExecutableName + '.exe')))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $candidates.Add((Join-Path $env:APPDATA ('npm\' + $ExecutableName + '.cmd')))
    }
    if ($ClientId -eq 'openai' -and -not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'))
        $codexBinRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
        if (Test-Path -LiteralPath $codexBinRoot -PathType Container) {
            Get-ChildItem -LiteralPath $codexBinRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | ForEach-Object {
                $candidates.Add((Join-Path $_.FullName 'codex.exe'))
            }
        }
    }
    if ($ClientId -eq 'openai' -and -not [string]::IsNullOrWhiteSpace($env:CODEX_INSTALL_DIR)) {
        $candidates.Add((Join-Path $env:CODEX_INSTALL_DIR 'codex.exe'))
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
    $scriptCommand = Get-Command $ExecutableName -CommandType ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($scriptCommand -and $scriptCommand.Source) { return $scriptCommand.Source }
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
            Detail = if ($restartRequired) { "$DisplayName must be restarted or reconnected to reload the MCP host." } elseif ($configuredWithoutCli) { "$DisplayName is configured." } elseif ($ClientId -eq 'openai') { 'Codex CLI not found. Automatic setup needs the Codex command-line tool (CLI). Having ChatGPT Desktop installed does not confirm that this tool is available. Install Codex CLI: https://learn.chatgpt.com/docs/codex/cli . Click Install on this card, confirm the official installer, then click Connect separately. Manual setup is also available.' } elseif ($ClientId -eq 'claudeCode') { 'Claude Code CLI not found. Automatic setup needs the Claude Code command-line tool (CLI). Having Claude Desktop installed does not confirm that this tool is available. Install Claude Code CLI: https://code.claude.com/docs/en/setup . Click Install on this card, confirm the official installer, then click Connect separately. Manual setup is also available.' } else { "$DisplayName CLI was not found. Use the manual STDIO values shown in 3ds Max." }
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
        $Status.State = $runtimeResult.State
        $Status.Configured = $false
        $Status.Detail = $runtimeResult.Detail
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
        $Status.State = $runtimeResult.State
        $Status.Configured = $false
        $Status.Detail = $runtimeResult.Detail
        return $Status
    }
    Invoke-ExternalCommand $Status.CommandPath @('mcp','remove',$serverName,'--scope','user') $DeadlineUtc $clientCommandTimeoutMilliseconds | Out-Null
    $install = Invoke-ExternalCommand $Status.CommandPath @('mcp','add',$serverName,'--scope','user','--env',"MAX_ULTRA_MCP_TOOL_PROFILE=$Profile",'--',$NodePath,$serverPath,'--stdio') $DeadlineUtc $clientCommandTimeoutMilliseconds
    $Status.Configured = -not $install.TimedOut -and -not $install.InvocationFailed -and $install.ExitCode -eq 0
    $Status.State = if ($Status.Configured) { 'configured' } else { 'install_failed' }
    $Status.Detail = if ($Status.Configured) { 'Claude Code integration was installed for the current Windows user.' } else { 'Installation failed. Run the client CLI manually for diagnostic output.' }
    return $Status
}

function Install-AntigravityClient($Status, [string]$NodePath, [DateTime]$DeadlineUtc) {
    if ($Status.setupAvailable -ne 'true') { return $Status }
    if ([string]::IsNullOrWhiteSpace($NodePath) -or -not (Test-Path -LiteralPath $serverPath -PathType Leaf)) {
        $Status.state = $runtimeResult.State
        $Status.detail = $runtimeResult.Detail
        return $Status
    }
    $configHelper = Join-Path $projectRoot 'core\antigravity-config.js'
    $install = Invoke-ExternalCommand $NodePath @($configHelper,'--config',$Status.configPath,'--node',$NodePath,'--server',$serverPath,'--profile',$Profile,'--port',[string]$Port) $DeadlineUtc 20000
    if ($install.TimedOut -or $install.InvocationFailed) {
        $Status.state = 'install_failed'
        $Status.detail = 'Setup did not finish. Refresh status before retrying; an existing backup is kept beside the settings file.'
        return $Status
    }
    try { $outcome = $install.Output | ConvertFrom-Json -ErrorAction Stop } catch {
        $Status.state = 'install_failed'
        $Status.detail = 'Setup could not report its result. Refresh status before retrying.'
        return $Status
    }
    $refreshed = Get-AntigravityStatus -NodePath $NodePath -ServerPath $serverPath -Profile $Profile -Port $Port
    $refreshed['backupPath'] = [string](Get-AntigravityProperty $outcome 'backupPath' '')
    if ($install.ExitCode -ne 0 -or -not $outcome.ok -or $refreshed.configured -ne 'true') {
        $refreshed.state = 'install_failed'
        $refreshed.detail = [string](Get-AntigravityProperty (Get-AntigravityProperty $outcome 'error') 'message' 'Could not verify saved settings. Refresh status and retry.')
    } else {
        $refreshed.detail = 'Setup complete. Use the Test prompt in Antigravity. If tools are unavailable, refresh its MCP servers or reopen Antigravity.'
    }
    return $refreshed
}

function Write-CliInstallProgress([string]$Message, [ValidateSet('info','success','warning')][string]$Kind = 'info') {
    if (-not (Get-Variable cliInstallStages -Scope Script -ErrorAction SilentlyContinue)) { $script:cliInstallStages = @() }
    if ($script:cliInstallStages.Count -eq 0) { $script:cliInstallStageKinds = @() }
    $script:cliInstallStages += $Message
    $script:cliInstallStageKinds += $Kind
    Write-IntegrationResult @{ operation = @{ state = 'running'; action = 'installcli'; message = $Message; stages = ($script:cliInstallStages -join '|'); stageKinds = ($script:cliInstallStageKinds -join '|') } }
}

function Install-ClientCli([hashtable]$Status, [bool]$Confirmed) {
    # A separate, explicitly confirmed action. Never register MCP from this function.
    if (-not $Confirmed) { throw 'CLI installation requires explicit confirmation.' }
    if ($script:integrationCancelPath -and (Test-Path -LiteralPath $script:integrationCancelPath)) {
        $Status.State = 'cli_install_failed'
        $Status.Detail = 'CLI installation cancelled. Refresh status before retrying.'
        $Status.DetailKind = 'warning'
        return $Status
    }
    if ($Status.Id -notin @('openai','claudeCode')) { throw 'Unsupported CLI installer.' }
    $executableName = if ($Status.Id -eq 'openai') { 'codex' } else { 'claude' }
    $existingCommand = Resolve-ClientCommandPath $Status.Id $executableName
    $savedRegistrationWithoutCli = $Status.State -in @('configured','restart_required') -and -not $Status.CliAvailable
    if (($Status.State -ne 'cli_missing' -and -not $savedRegistrationWithoutCli) -or $existingCommand) {
        $Status.Detail = 'CLI installation was not started because the client is present or its status is uncertain. Refresh status.'
        Write-CliInstallProgress $Status.Detail
        return $Status
    }
    $installerUrl = if ($Status.Id -eq 'openai') { 'https://chatgpt.com/codex/install.ps1' } else { 'https://claude.ai/install.ps1' }
    Write-CliInstallProgress 'Running the official CLI installer (download and installation). Please wait; this may take a few minutes, depending on your connection.'
    $installerCommand = '$ErrorActionPreference = ''Stop''; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; irm ' + $installerUrl + ' | iex'
    if ($Status.Id -eq 'openai') { $installerCommand = '$env:CODEX_NON_INTERACTIVE = ''1''; ' + $installerCommand }
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($installerCommand))
    $powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $install = Invoke-ExternalCommand $powershellPath @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encodedCommand) ([DateTime]::UtcNow.AddSeconds(300)) 300000
    $Status.State = 'cli_install_failed'
    if ($install.ContainsKey('Cancelled') -and $install.Cancelled) {
        $Status.Detail = 'CLI installation cancelled. Some files may have been installed. Refresh status before retrying.'
        $Status.DetailKind = 'warning'
        return $Status
    }
    if ($install.TimedOut -or $install.InvocationFailed -or $install.ExitCode -ne 0) {
        $reason = if ($install.TimedOut) { 'timed out after five minutes' } elseif ($install.InvocationFailed) { 'could not start PowerShell' } else { 'failed (exit ' + $install.ExitCode + ')' }
        $Status.Detail = 'Official CLI installer ' + $reason + '. Check network access and your security software, or use the official instructions: ' + $(if ($Status.Id -eq 'openai') { 'https://learn.chatgpt.com/docs/codex/cli' } else { 'https://code.claude.com/docs/en/setup' }) + '. Refresh status before retrying.'
        return $Status
    }
    # Max may predate a PATH update. Refresh this helper process only, never machine settings.
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User') + ';' + $env:PATH
    Write-CliInstallProgress 'Installer finished. Rediscovering and verifying the CLI...'
    $commandPath = Resolve-ClientCommandPath $Status.Id $executableName
    if (-not $commandPath) {
        $Status.Detail = 'Installer finished but the CLI was not found. Open a new terminal and check its version, then refresh status. MCP was not registered.'
        return $Status
    }
    $Status.CommandPath = $commandPath
    $Status.CliAvailable = $true
    $probe = Invoke-ExternalCommand $commandPath @('--version') ([DateTime]::UtcNow.AddSeconds(15)) 10000
    if ($probe.TimedOut -or $probe.InvocationFailed -or $probe.ExitCode -ne 0 -or -not $probe.ContainsKey('StandardOutput') -or $probe.StandardOutput -notmatch '\d+\.\d+\.\d+') {
        return New-ClientCheckFailedStatus $Status.Id $Status.DisplayName $commandPath $probe.TimedOut
    }
    $Status.State = if ($Status.Configured) { 'configured' } else { 'not_configured' }
    Write-CliInstallProgress 'Setup CLI installed and verified.' 'success'
    $Status.Detail = 'Setup CLI installed and verified. Click Connect to ' + $(if ($Status.Id -eq 'openai') { 'Codex' } else { 'Claude Code' }) + ' to register MCP. Sign in and chat in the desktop app; terminal chat is not required.'
    return $Status
}

try {
    $script:cliInstallStages = @()
    $script:cliInstallStageKinds = @()
    if ($Action -eq 'InstallCli') { Write-CliInstallProgress 'Checking installed components...' }
    $runtimeResult = Resolve-NodeRuntime $statusCheckDeadlineUtc
    $nodePath = $runtimeResult.Command
    $antigravity = Get-AntigravityStatus -NodePath $nodePath -ServerPath $serverPath -Profile $Profile -Port $Port
    $openAI = Get-ClientStatus 'openai' 'ChatGPT Desktop / Codex' 'codex' ([DateTime]::UtcNow.AddSeconds(22))
    $claudeCode = Get-ClientStatus 'claudeCode' 'Claude Code' 'claude' ([DateTime]::UtcNow.AddSeconds(22))
    $openAIDesktop = Get-DesktopClientStatus 'openai'
    $claudeDesktop = Get-DesktopClientStatus 'claudeCode'

    if ($Action -eq 'InstallCli') {
        if (-not $ConfirmCliInstall -or $InstallAntigravity -or ($InstallOpenAI -eq $InstallClaudeCode)) { throw 'Confirm installation of exactly one supported CLI.' }
        if ($InstallOpenAI) { $openAI = Install-ClientCli $openAI $true }
        if ($InstallClaudeCode) { $claudeCode = Install-ClientCli $claudeCode $true }
        $openAIDesktop = Get-DesktopClientStatus 'openai'
        $claudeDesktop = Get-DesktopClientStatus 'claudeCode'
    }

    if ($Action -eq 'Install') {
        $installDeadlineUtc = [DateTime]::UtcNow.AddSeconds(90)
        if ($InstallOpenAI -and $openAIDesktop.Available) { $openAI = Install-OpenAIClient $openAI $nodePath $installDeadlineUtc }
        if ($InstallClaudeCode -and $claudeDesktop.Available) { $claudeCode = Install-ClaudeCodeClient $claudeCode $nodePath $installDeadlineUtc }
        if ($InstallAntigravity -and $antigravity.installed -eq 'true') { $antigravity = Install-AntigravityClient $antigravity $nodePath $installDeadlineUtc }
    }

    $openAI = Add-DesktopClientStatus $openAI $openAIDesktop
    $claudeCode = Add-DesktopClientStatus $claudeCode $claudeDesktop
    $antigravity['desktopAvailable'] = $antigravity.installed
    $antigravity['desktopState'] = if ($antigravity.installed -eq 'true') { 'installed' } else { 'missing' }
    $antigravity['desktopInstallUrl'] = 'https://antigravity.google/download'
    $antigravity['desktopInstructions'] = 'Install Antigravity 2.0 for Windows from the official page, then open its desktop app and sign in. Refresh status here, click Connect to Antigravity, and run Test prompt in its desktop chat. No separate Antigravity CLI is required.'
    $runtimeReady = -not [string]::IsNullOrWhiteSpace($nodePath) -and (Test-Path -LiteralPath $serverPath -PathType Leaf)
    $message = if ($Action -eq 'Install') { 'Selected integrations were processed. Restart or reconnect the configured AI clients.' } else { 'Integration status was refreshed.' }
    if ($Action -eq 'InstallCli') { $message = 'CLI installation result is shown on the selected card. Connect is a separate step.' }
    if ($Action -eq 'Install' -and $InstallAntigravity -and -not $InstallOpenAI -and -not $InstallClaudeCode) {
        $message = if ($antigravity.state -eq 'configured') { 'Antigravity settings saved. Run the Test prompt.' } else { 'Antigravity setup needs attention.' }
    }
    Write-IntegrationResult ([ordered]@{
        operation = [ordered]@{ state = 'complete'; action = $Action.ToLowerInvariant(); message = $message; stages = ($script:cliInstallStages -join '|'); stageKinds = ($script:cliInstallStageKinds -join '|') }
        openai = ConvertTo-ClientResult $openAI
        claudeCode = ConvertTo-ClientResult $claudeCode
        antigravity = $antigravity
        runtime = [ordered]@{ ready = $runtimeReady.ToString().ToLowerInvariant(); state = $runtimeResult.State; detail = $runtimeResult.Detail; candidate = $runtimeResult.Candidate; command = $nodePath; server = $serverPath; arguments = '"' + $serverPath + '" --stdio'; environment = "MAX_ULTRA_MCP_TOOL_PROFILE=$Profile" }
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
