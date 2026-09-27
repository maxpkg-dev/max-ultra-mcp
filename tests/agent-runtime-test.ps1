# Tests setup runtime probes without configuring clients or opening a Max scene.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
function Assert-Runtime([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$helperSource = [IO.File]::ReadAllText((Join-Path $repositoryRoot 'scripts\agent-integration.ps1'))
$parseTokens = $null
$parseErrors = $null
$helperAst = [Management.Automation.Language.Parser]::ParseInput($helperSource, [ref]$parseTokens, [ref]$parseErrors)
Assert-Runtime ($parseErrors.Count -eq 0) 'Integration helper syntax failed.'
foreach ($functionName in @('ConvertTo-ProcessArgument','Get-RemainingTimeoutMilliseconds','Stop-ExternalCommandProcess','Invoke-ExternalCommand','Test-NodeRuntimeCandidate','Resolve-NodeRuntime','Install-OpenAIClient','Install-ClaudeCodeClient','Install-AntigravityClient')) {
    $functionAst = $helperAst.Find({param($syntaxNode) $syntaxNode -is [Management.Automation.Language.FunctionDefinitionAst] -and $syntaxNode.Name -eq $functionName}, $true)
    . ([scriptblock]::Create($functionAst.Extent.Text))
}
$realInvoker = (Get-Item Function:Invoke-ExternalCommand).ScriptBlock
$nodeProbeTimeoutMilliseconds = 5000
$nodeExecutable = Join-Path $repositoryRoot 'runtime\win-x64\node.exe'
if (-not (Test-Path -LiteralPath $nodeExecutable)) { $nodeExecutable = (Get-Command node -CommandType Application | Select-Object -First 1).Source }
# Exercise the real redirected process reader repeatedly, including stderr alongside valid stdout.
for ($probeIndex = 0; $probeIndex -lt 30; $probeIndex++) {
    $probe = Invoke-ExternalCommand $nodeExecutable @('-e', 'process.stdout.write(process.versions.node); process.stderr.write("diagnostic")') ([DateTime]::UtcNow.AddSeconds(10)) 5000
    Assert-Runtime (-not $probe.InvocationFailed -and -not $probe.TimedOut -and $probe.ExitCode -eq 0) 'Version process failed.'
    Assert-Runtime ($probe.StandardOutput -match '^\d+\.\d+\.\d+$') 'Version stdout was lost or polluted by stderr.'
}
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('max-ultra-runtime-test-' + [Guid]::NewGuid().ToString('N'))
$savedEnvironment = @{}
try {
    $projectRoot = Join-Path $fixtureRoot 'Package With Spaces'
    $serverPath = Join-Path $projectRoot 'core\server.js'
    $candidatePath = Join-Path $projectRoot 'runtime\win-x64\node.exe'
    foreach ($fixtureFile in @($serverPath, $candidatePath)) {
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $fixtureFile))
        [IO.File]::WriteAllText($fixtureFile, 'synthetic fixture')
    }
    $script:probeCalls = 0
    function Invoke-ExternalCommand { $script:probeCalls++; return $script:fakeProbe }
    foreach ($testCase in @(
        @('ready', $false, $false, 0, '24.18.0'),
        @('runtime_timeout', $true, $false, -1, ''),
        @('runtime_launch_failed', $false, $true, -1, ''),
        @('runtime_launch_failed', $false, $false, 5, ''),
        @('runtime_unsupported', $false, $false, 0, '20.0.0'),
        @('runtime_invalid_response', $false, $false, 0, ''),
        @('runtime_invalid_response', $false, $false, 0, 'not a version')
    )) {
        $script:fakeProbe = @{ TimedOut=$testCase[1]; InvocationFailed=$testCase[2]; ExitCode=$testCase[3]; StandardOutput=$testCase[4] }
        $runtimeResult = Test-NodeRuntimeCandidate $candidatePath ([DateTime]::UtcNow.AddSeconds(10))
        Assert-Runtime ($runtimeResult.State -eq $testCase[0]) ('Wrong runtime state: ' + $testCase[0])
        Assert-Runtime ($runtimeResult.Detail.Contains($candidatePath)) 'Diagnostics lost checked path.'
        if ($runtimeResult.State -ne 'ready') {
            $clientStatus = @{ CliAvailable=$true; Configured=$false; State='not_configured'; Detail='' }
            $beforeCalls = $script:probeCalls
            $installStatus = Install-OpenAIClient $clientStatus '' ([DateTime]::UtcNow.AddSeconds(10))
            Assert-Runtime ($installStatus.State -eq $testCase[0] -and $script:probeCalls -eq $beforeCalls) 'Failed runtime invoked or misreported client installation.'
        }
    }
    $missing = Test-NodeRuntimeCandidate (Join-Path $fixtureRoot 'missing.exe') ([DateTime]::UtcNow.AddSeconds(10))
    Assert-Runtime ($missing.State -eq 'runtime_missing') 'Missing executable not distinguished.'
    foreach ($environmentKey in @('PATH','USERPROFILE','LOCALAPPDATA')) {
        $savedEnvironment[$environmentKey] = [Environment]::GetEnvironmentVariable($environmentKey)
        [Environment]::SetEnvironmentVariable($environmentKey, $fixtureRoot)
    }
    $script:fakeProbe = @{ TimedOut=$true; InvocationFailed=$false; ExitCode=-1; StandardOutput='' }
    $runtimeResult = Resolve-NodeRuntime ([DateTime]::UtcNow.AddSeconds(10))
    Assert-Runtime ($runtimeResult.State -eq 'runtime_timeout') 'Resolver collapsed timeout into missing.'
    $fallbackPath = Join-Path $fixtureRoot 'node.exe'
    $bundledFixturePath = $candidatePath
    [IO.File]::WriteAllText($fallbackPath, 'synthetic fallback')
    function Invoke-ExternalCommand([string]$CommandPath) {
        if ($CommandPath -eq $bundledFixturePath) { return @{TimedOut=$true; InvocationFailed=$false; ExitCode=-1; StandardOutput=''} }
        return @{TimedOut=$false; InvocationFailed=$false; ExitCode=0; StandardOutput='24.18.0'}
    }
    $runtimeResult = Resolve-NodeRuntime ([DateTime]::UtcNow.AddSeconds(10))
    Assert-Runtime ($runtimeResult.State -eq 'ready' -and $runtimeResult.Command -eq $fallbackPath) 'Timed-out bundled probe blocked a valid fallback.'
    Remove-Item -LiteralPath $serverPath
    $runtimeResult = Resolve-NodeRuntime ([DateTime]::UtcNow.AddSeconds(10))
    Assert-Runtime ($runtimeResult.State -eq 'runtime_missing' -and $runtimeResult.Candidate -eq $serverPath) 'Missing server file not identified.'
    Write-Output 'Setup runtime tests passed: redirected output, error states, install guard, fallback, missing server (isolated fixtures).'
} finally {
    foreach ($environmentKey in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($environmentKey, $savedEnvironment[$environmentKey]) }
    Set-Item Function:Invoke-ExternalCommand $realInvoker
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedFixture.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolvedFixture) -notlike 'max-ultra-runtime-test-*') { throw 'Unsafe fixture cleanup path.' }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
