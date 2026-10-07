# Verifies independent desktop discovery with synthetic files and mocked package enumeration.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
function Assert-Desktop([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repositoryRoot 'scripts\agent-integration.ps1'), [ref]$tokens, [ref]$errors)
Assert-Desktop ($errors.Count -eq 0) 'Integration helper syntax failed.'
foreach ($definition in $ast.FindAll({param($entry) $entry -is [Management.Automation.Language.FunctionDefinitionAst]}, $false)) { . ([scriptblock]::Create($definition.Extent.Text)) }
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('max-ultra-desktop-test-' + [Guid]::NewGuid().ToString('N'))
$savedLocal = $env:LOCALAPPDATA
$savedArchitecture = $env:PROCESSOR_ARCHITECTURE
$savedNativeArchitecture = $env:PROCESSOR_ARCHITEW6432
$script:stagingRoots = @()
$script:integrationCancelPath = ''
try {
    [void][IO.Directory]::CreateDirectory($fixtureRoot)
    $env:LOCALAPPDATA = $fixtureRoot
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $env:PROCESSOR_ARCHITEW6432 = 'AMD64'
    function Get-AppxPackage { return @() }
    Assert-Desktop ((Get-DesktopClientStatus 'openai').State -eq 'missing') 'Absent desktop app was not missing.'
    # A standalone CLI is not desktop installation evidence.
    $cliPath = Join-Path $fixtureRoot 'Programs\OpenAI\Codex\bin\codex.exe'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $cliPath))
    [IO.File]::WriteAllText($cliPath, 'synthetic CLI')
    Assert-Desktop (-not (Get-DesktopClientStatus 'openai').Available) 'CLI-only install claimed desktop readiness.'
    function Get-AppxPackage { return @([pscustomobject]@{Status='Ok'; IsFramework=$false}) }
    Assert-Desktop ((Get-DesktopClientStatus 'openai').Available) 'Registered desktop package was not detected.'
    function Get-AppxPackage { throw 'synthetic discovery failure' }
    Assert-Desktop ((Get-DesktopClientStatus 'claudeCode').State -eq 'check_failed') 'Desktop discovery failure was treated as missing.'
    $appPath = Join-Path $fixtureRoot 'AnthropicClaude\claude.exe'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $appPath))
    [IO.File]::WriteAllText($appPath, 'synthetic desktop')
    Assert-Desktop ((Get-DesktopClientStatus 'claudeCode').Available) 'Classic desktop evidence was ignored.'
    $componentStatus = @{Id='claudeCode'; State='cli_missing'; CliAvailable=$false; Configured=$false; Detail='Setup CLI missing.'}
    $combined = Add-DesktopClientStatus $componentStatus @{Available=$true; State='installed'; Detail='Desktop found.'}
    $serialized = ConvertTo-ClientResult $combined
    Assert-Desktop ($serialized.desktopAvailable -eq 'true' -and $serialized.cliAvailable -eq 'false') 'Independent component state was lost.'
    Assert-Desktop ($serialized.desktopInstructions -match 'Code tab' -and $serialized.desktopInstructions -match 'Local session') 'Claude desktop target is ambiguous.'

    Write-Output 'Desktop discovery tests passed: separate CLI/app evidence, package failures, classic app and desktop session guidance.'
} finally {
    $env:LOCALAPPDATA = $savedLocal
    $env:PROCESSOR_ARCHITECTURE = $savedArchitecture
    $env:PROCESSOR_ARCHITEW6432 = $savedNativeArchitecture
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolved = [IO.Path]::GetFullPath($fixtureRoot)
    if (-not $resolved.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolved) -notlike 'max-ultra-desktop-test-*') { throw 'Unsafe test cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
