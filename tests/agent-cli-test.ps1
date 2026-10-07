# Tests CLI discovery and confirmed installation using isolated files and mocked installers.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
function Assert-Cli([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repositoryRoot 'scripts\agent-integration.ps1'), [ref]$tokens, [ref]$errors)
Assert-Cli ($errors.Count -eq 0) 'Helper syntax failed.'
foreach ($definition in $ast.FindAll({ param($entry) $entry -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($definition.Extent.Text))
}
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('max-ultra-cli-test-' + [Guid]::NewGuid().ToString('N'))
$savedEnvironment = @{}
$serverName = 'max-ultra-mcp'
$clientCommandTimeoutMilliseconds = 10000
$script:integrationCancelPath = ''
try {
    [void][IO.Directory]::CreateDirectory($fixtureRoot)
    foreach ($key in @('PATH','USERPROFILE','APPDATA','LOCALAPPDATA','CODEX_INSTALL_DIR')) {
        $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key)
        [Environment]::SetEnvironmentVariable($key, $fixtureRoot)
    }
    $wrapperPath = Join-Path $fixtureRoot 'codex.ps1'
    [IO.File]::WriteAllText($wrapperPath, '[Console]::WriteLine("header"); [Console]::WriteLine("max-ultra-mcp ready")')
    Assert-Cli ((Resolve-ClientCommandPath 'openai' 'codex') -eq $wrapperPath) 'Script-only CLI was not discovered.'
    $probe = Invoke-ExternalCommand $wrapperPath @() ([DateTime]::UtcNow.AddSeconds(10)) 5000
    Assert-Cli ($probe.ExitCode -eq 0 -and $probe.Output -match '(?m)^max-ultra-mcp ') 'PowerShell wrapper launch or multiline output failed.'
    $script:integrationCancelPath = Join-Path $fixtureRoot 'process.cancel'
    [IO.File]::WriteAllText($wrapperPath, 'param([string]$CancelPath) [IO.File]::WriteAllText($CancelPath, "cancel"); Start-Sleep -Seconds 20')
    $probe = Invoke-ExternalCommand $wrapperPath @($script:integrationCancelPath) ([DateTime]::UtcNow.AddSeconds(10)) 5000
    Assert-Cli ($probe.ContainsKey('Cancelled') -and $probe.Cancelled) 'Running helper did not honor cancellation.'
    Remove-Item -LiteralPath $script:integrationCancelPath
    $script:integrationCancelPath = ''
    [IO.File]::WriteAllText($wrapperPath, 'Start-Sleep -Seconds 20')
    $probe = Invoke-ExternalCommand $wrapperPath @() ([DateTime]::UtcNow.AddSeconds(10)) 200
    Assert-Cli ($probe.TimedOut) 'Command timeout was not bounded.'
    $applicationPath = Join-Path $fixtureRoot 'codex.cmd'
    [IO.File]::WriteAllText($applicationPath, '@echo synthetic')
    Assert-Cli ((Resolve-ClientCommandPath 'openai' 'codex') -eq $applicationPath) 'Application shim did not win over PowerShell wrapper.'
    Remove-Item -LiteralPath $applicationPath, $wrapperPath
    $standalonePath = Join-Path $fixtureRoot 'Programs\OpenAI\Codex\bin\codex.exe'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $standalonePath))
    [IO.File]::WriteAllText($standalonePath, 'synthetic standalone fixture')
    Assert-Cli ((Resolve-ClientCommandPath 'openai' 'codex') -eq $standalonePath) 'Standalone Codex was not discovered outside PATH.'
    Remove-Item -LiteralPath $standalonePath
    Assert-Cli ($null -eq (Resolve-ClientCommandPath 'claudeCode' 'claude')) 'Missing client was not absent.'
    function Test-StdioHostRestartRequired { return $false }
    function Resolve-ClientCommandPath { return 'synthetic-cli.exe' }
    function Invoke-ExternalCommand($CommandPath, $Arguments) {
        if ($Arguments[1] -eq 'get') { return @{ExitCode=1; Output=''; TimedOut=$false; InvocationFailed=$false} }
        return @{ExitCode=0; Output="Name Command`nmax-ultra-mcp synthetic"; TimedOut=$false; InvocationFailed=$false}
    }
    $status = Get-ClientStatus 'claudeCode' 'Claude Code' 'claude' ([DateTime]::UtcNow.AddSeconds(22))
    Assert-Cli ($status.State -eq 'configured') 'Fallback list lost registration after a header.'
    function Invoke-ExternalCommand { return @{ExitCode=-1; Output=''; TimedOut=$false; InvocationFailed=$true} }
    $status = Get-ClientStatus 'claudeCode' 'Claude Code' 'claude' ([DateTime]::UtcNow.AddSeconds(22))
    Assert-Cli ($status.State -eq 'check_failed' -and $status.CliAvailable) 'Unlaunchable CLI was treated as missing.'

    $script:installerCalls = 0
    $script:resolvedCommand = $null
    function Resolve-ClientCommandPath { return $script:resolvedCommand }
    $script:progressSnapshots = @()
    function Write-IntegrationResult($Value) { $script:progressSnapshots += $Value.operation.stages }
    function New-MissingStatus { return @{Id='claudeCode'; DisplayName='Claude Code'; State='cli_missing'; CliAvailable=$false; Configured=$false; CommandPath=''; Detail=''} }
    function Invoke-ExternalCommand($CommandPath, $Arguments) {
        $script:installerCalls++
        Assert-Cli ($Arguments -notcontains 'mcp') 'CLI installation registered MCP without a second click.'
        if ($Arguments -contains '-EncodedCommand') {
            $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Arguments[-1]))
            Assert-Cli ($decoded.Contains('https://claude.ai/install.ps1') -or $decoded.Contains('https://chatgpt.com/codex/install.ps1')) 'Unexpected installer source.'
            $script:resolvedCommand = 'synthetic-cli.exe'
        }
        return @{ExitCode=0; Output=''; StandardOutput='2.1.0'; TimedOut=$false; InvocationFailed=$false}
    }
    $rejected = $false
    try { Install-ClientCli (New-MissingStatus) $false | Out-Null } catch { $rejected = $true }
    Assert-Cli ($rejected -and $script:installerCalls -eq 0) 'Unconfirmed install ran.'
    foreach ($clientId in @('openai','claudeCode')) {
        $script:cliInstallStages = @()
        $script:progressSnapshots = @()
        $script:resolvedCommand = $null
        $missing = New-MissingStatus
        $missing.Id = $clientId
        $installed = Install-ClientCli $missing $true
        Assert-Cli ($installed.State -eq 'not_configured' -and $installed.CliAvailable -and -not $installed.Configured) 'Install did not leave a separate Connect step.'
        Assert-Cli ($script:cliInstallStages.Count -eq 3 -and $script:cliInstallStages[0] -match 'download and installation' -and $script:cliInstallStages[1] -match 'verifying' -and $script:cliInstallStages[2] -eq 'Setup CLI installed and verified.') 'CLI progress did not preserve observable stage order.'
        Assert-Cli ($script:progressSnapshots[-1] -eq ($script:cliInstallStages -join '|')) 'Final progress snapshot lost earlier stages between UI polls.'
        Assert-Cli ($script:cliInstallStages[0] -match 'Please wait; this may take a few minutes') 'Installer stage does not explain the wait.'
        Assert-Cli (($script:cliInstallStageKinds -join '|') -eq 'info|info|success') 'Only verified CLI completion may be a success; running and verifying must remain info.'
    }
    $script:resolvedCommand = $null
    $savedRegistration = New-MissingStatus
    $savedRegistration.State = 'configured'
    $savedRegistration.Configured = $true
    $restoredCli = Install-ClientCli $savedRegistration $true
    Assert-Cli ($restoredCli.CliAvailable -and $restoredCli.Configured -and $restoredCli.State -eq 'configured') 'Saved registration prevented missing CLI setup or was lost.'
    $beforeCalls = $script:installerCalls
    Install-ClientCli (New-MissingStatus) $true | Out-Null
    Assert-Cli ($script:installerCalls -eq $beforeCalls) 'Stale missing state reinstalled a present client.'
    $script:resolvedCommand = $null
    $failed = New-MissingStatus
    $failed.State = 'check_failed'
    Install-ClientCli $failed $true | Out-Null
    Assert-Cli ($script:installerCalls -eq $beforeCalls) 'Failed probe offered reinstall.'
    foreach ($outcome in @(
        @{ExitCode=-1; TimedOut=$true; InvocationFailed=$false},
        @{ExitCode=2; TimedOut=$false; InvocationFailed=$false},
        @{ExitCode=-1; TimedOut=$false; InvocationFailed=$true},
        @{ExitCode=-1; TimedOut=$false; InvocationFailed=$false; Cancelled=$true}
    )) {
        $script:cliInstallStages = @()
        $script:fakeOutcome = $outcome
        function Invoke-ExternalCommand { return $script:fakeOutcome }
        $failed = Install-ClientCli (New-MissingStatus) $true
        Assert-Cli ($failed.State -eq 'cli_install_failed' -and -not $failed.Configured) 'Installer failure was hidden.'
        Assert-Cli (($script:cliInstallStages -join '|') -notmatch 'installed and verified') 'Failed or cancelled installer reported completion.'
        Assert-Cli ($script:cliInstallStageKinds -notcontains 'success') 'Failure or cancellation emitted a green success stage.'
    }
    function Invoke-ExternalCommand { return @{ExitCode=0; TimedOut=$false; InvocationFailed=$false} }
    $missingAfterInstall = Install-ClientCli (New-MissingStatus) $true
    Assert-Cli ($missingAfterInstall.State -eq 'cli_install_failed') 'Successful installer exit without a CLI claimed success.'
    function Invoke-ExternalCommand($CommandPath, $Arguments) {
        if ($Arguments -contains '-EncodedCommand') {
            $script:resolvedCommand = 'synthetic-cli.exe'
            return @{ExitCode=0; TimedOut=$false; InvocationFailed=$false}
        }
        return @{ExitCode=-1; TimedOut=$false; InvocationFailed=$true}
    }
    $badVersion = Install-ClientCli (New-MissingStatus) $true
    Assert-Cli ($badVersion.State -eq 'check_failed' -and $badVersion.CliAvailable) 'Unlaunchable installed CLI claimed readiness.'
    $script:integrationCancelPath = Join-Path $fixtureRoot 'cancel'
    [IO.File]::WriteAllText($script:integrationCancelPath, 'cancel')
    function Invoke-ExternalCommand { throw 'Cancelled operation launched a process.' }
    $cancelled = Install-ClientCli (New-MissingStatus) $true
    Assert-Cli ($cancelled.Detail -match 'cancelled') 'Early cancellation failed.'
    Assert-Cli ($cancelled.DetailKind -eq 'warning') 'User cancellation is a warning, not a successful install or an unexpected error.'
    Write-Output 'CLI setup tests passed: wrappers, multiline detection, failed probes, confirmation, separate connect, stale state, failures and cancellation (no external installers).'
} finally {
    foreach ($key in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key]) }
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedFixture.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolvedFixture) -notlike 'max-ultra-cli-test-*') { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
