# Tests Antigravity setup against isolated fixtures without launching any AI client.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\antigravity-integration.ps1')
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('max-ultra-antigravity-' + [Guid]::NewGuid().ToString('N'))
try {
    $profileRoot = Join-Path $fixtureRoot 'Example User'
    $localRoot = Join-Path $fixtureRoot 'Local'
    $configPath = Join-Path $profileRoot '.gemini\config\mcp_config.json'
    $nodePath = Join-Path $fixtureRoot 'Package With Spaces\node.exe'
    $serverPath = Join-Path $fixtureRoot 'Package With Spaces\server.js'
    $appPath = Join-Path $localRoot 'Programs\antigravity\Antigravity.exe'
    foreach ($filePath in @($configPath, $nodePath, $serverPath, $appPath)) {
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $filePath))
    }
    [IO.File]::WriteAllText($nodePath, '')
    [IO.File]::WriteAllText($serverPath, '')
    $options = @{ NodePath=$nodePath; ServerPath=$serverPath; UserProfilePath=$profileRoot; LocalAppDataPath=$localRoot; ProgramRoots=@(); Profile='archviz'; Port=47635 }
    $status = Get-AntigravityStatus @options
    Assert-True ($status.installed -eq 'false' -and $status.configured -eq 'false') 'Missing app must not be ready.'
    Assert-True (-not (Test-Path $configPath)) 'Status must not create client settings.'
    [IO.File]::WriteAllText($appPath, '')
    [IO.File]::WriteAllText($configPath, '')
    $status = Get-AntigravityStatus @options
    Assert-True ($status.installed -eq 'true' -and $status.state -eq 'not_configured') 'Empty settings must require setup.'
    $setup = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($status.setupBase64))
    $parsed = $setup | ConvertFrom-Json
    Assert-True ($parsed.mcpServers.'max-ultra-mcp'.command -eq $nodePath) 'JSON must preserve spaces without embedded shell quotes.'
    Assert-True ($parsed.mcpServers.'max-ultra-mcp'.args[0] -eq $serverPath) 'JSON must preserve server path.'
    Assert-True ($setup -notmatch 'TOKEN|LOCALAPPDATA') 'Setup must not export secrets or user environment.'
    [IO.File]::WriteAllText($configPath, $setup)
    $beforeHash = (Get-FileHash $configPath).Hash
    $status = Get-AntigravityStatus @options
    Assert-True ($status.configured -eq 'true' -and $status.connection -eq 'unverified') 'Matching configuration is not proof of connection.'
    Assert-True ((Get-FileHash $configPath).Hash -eq $beforeHash) 'Status must never rewrite settings.'
    foreach ($case in @('disabled', 'wrong_path', 'wrong_port', 'wrong_profile', 'restricted', 'token_override')) {
        $parsed = $setup | ConvertFrom-Json
        $entry = $parsed.mcpServers.'max-ultra-mcp'
        switch ($case) {
            disabled { $entry | Add-Member disabled $true }
            wrong_path { $entry.command = Join-Path $fixtureRoot 'Other\node.exe' }
            wrong_port { $entry.env | Add-Member MAX_ULTRA_MCP_PORT '47636' }
            wrong_profile { $entry.env.MAX_ULTRA_MCP_TOOL_PROFILE = 'full' }
            restricted { $entry | Add-Member disabledTools @('max_list_instances') }
            token_override { $entry.env | Add-Member MAX_ULTRA_MCP_CONTROL_TOKEN 'synthetic-redacted' }
        }
        [IO.File]::WriteAllText($configPath, ($parsed | ConvertTo-Json -Depth 8))
        Assert-True ((Get-AntigravityStatus @options).configured -eq 'false') "Invalid registration accepted: $case"
    }
    foreach ($invalid in @('{broken', 'null', '[]', '{"mcpServers":[]}')) {
        [IO.File]::WriteAllText($configPath, $invalid)
        Assert-True ((Get-AntigravityStatus @options).state -eq 'check_failed') "Malformed settings must fail: $invalid"
    }
    $options.Port = 47636
    $options.Profile = 'full'
    $alternate = New-AntigravityConfiguration $nodePath $serverPath 'full' 47636
    [IO.File]::WriteAllText($configPath, $alternate)
    Assert-True ((Get-AntigravityStatus @options).configured -eq 'true') 'Fallback port and profile must round trip.'
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $powershellPath = Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
    $integrationPath = Join-Path $repositoryRoot 'scripts\agent-integration.ps1'
    $resultPath = Join-Path $fixtureRoot 'integration.ini'
    if (-not (Test-Path (Join-Path $repositoryRoot 'runtime\win-x64\node.exe'))) {
        $testNode = Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $fixtureNode = Join-Path $profileRoot '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $fixtureNode))
        Copy-Item -LiteralPath $testNode.Source -Destination $fixtureNode
    }
    $savedEnvironment = @{}
    foreach ($environmentKey in @('PATH', 'USERPROFILE', 'LOCALAPPDATA', 'APPDATA', 'ProgramFiles', 'ProgramFiles(x86)')) {
        $savedEnvironment[$environmentKey] = [Environment]::GetEnvironmentVariable($environmentKey)
    }
    try {
        $env:PATH = [Environment]::SystemDirectory
        $env:USERPROFILE = $profileRoot
        $env:LOCALAPPDATA = $localRoot
        $env:APPDATA = Join-Path $fixtureRoot 'Roaming'
        $env:ProgramFiles = Join-Path $fixtureRoot 'Programs'
        ${env:ProgramFiles(x86)} = Join-Path $fixtureRoot 'Programs32'
        [IO.File]::WriteAllText($configPath, '')
        & $powershellPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $integrationPath -Action Status -ResultPath $resultPath -Profile full -Port 47636
        Assert-True ($LASTEXITCODE -eq 0) 'Combined status helper failed.'
        $integrationText = [IO.File]::ReadAllText($resultPath)
        Assert-True ($integrationText -match '(?m)^\[antigravity\]') 'Combined result must include Antigravity.'
        Assert-True ($integrationText -match '(?m)^\[openai\]' -and $integrationText -match '(?m)^\[claudeCode\]') 'Existing client sections must be preserved.'
        $payloadMatch = [regex]::Match($integrationText, '(?m)^setupBase64=([^\r\n]+)')
        Assert-True $payloadMatch.Success 'Combined helper must prepare copyable settings with the resolved runtime.'
        $combinedJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payloadMatch.Groups[1].Value))
        $combinedEntry = ($combinedJson | ConvertFrom-Json).mcpServers.'max-ultra-mcp'
        Assert-True ($combinedEntry.env.MAX_ULTRA_MCP_PORT -eq '47636' -and $combinedEntry.env.MAX_ULTRA_MCP_TOOL_PROFILE -eq 'full') 'Combined helper must preserve requested port and profile.'
        Assert-True ((Get-Item $configPath).Length -eq 0) 'Combined helper must not populate client settings.'
        & $powershellPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $integrationPath -Action Install -InstallAntigravity -ResultPath $resultPath -Profile full -Port 47636
        Assert-True ($LASTEXITCODE -eq 0) 'Combined Antigravity installation failed.'
        $installedEntry = ([IO.File]::ReadAllText($configPath) | ConvertFrom-Json).mcpServers.'max-ultra-mcp'
        Assert-True ($installedEntry.command -eq $combinedEntry.command -and $installedEntry.args[0] -eq $combinedEntry.args[0]) 'Install selected must use the resolved runtime and server.'
        Assert-True ($installedEntry.env.MAX_ULTRA_MCP_PORT -eq '47636') 'Install selected lost the active bridge port.'
        $backups = @(Get-ChildItem -LiteralPath (Split-Path $configPath -Parent) -Filter '*.bak')
        Assert-True ($backups.Count -eq 1 -and $backups[0].Length -eq 0) 'Existing empty config must be backed up before installation.'
        $installedHash = (Get-FileHash $configPath).Hash
        & $powershellPath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $integrationPath -Action Install -InstallAntigravity -ResultPath $resultPath -Profile full -Port 47636
        Assert-True ((Get-FileHash $configPath).Hash -eq $installedHash -and @(Get-ChildItem -LiteralPath (Split-Path $configPath -Parent) -Filter '*.bak').Count -eq 1) 'Repeated installation must not rewrite or duplicate backups.'
    } finally {
        foreach ($environmentKey in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($environmentKey, $savedEnvironment[$environmentKey]) }
    }
    Write-Output 'Antigravity setup tests passed (isolated fixtures, no live configuration changes).'
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolvedFixture.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolvedFixture) -notlike 'max-ultra-antigravity-*') { throw 'Unsafe fixture cleanup path.' }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
