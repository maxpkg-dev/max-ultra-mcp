# Reads Antigravity registration and prepares verified automatic setup options.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

function Get-AntigravityProperty($Value, [string]$Key, $Fallback = $null) {
    if ($null -ne $Value -and $null -ne $Value.PSObject.Properties[$Key]) { return $Value.$Key }
    return $Fallback
}

function New-AntigravityConfiguration([string]$NodePath, [string]$ServerPath, [string]$Profile, [int]$Port = 47635) {
    if ($Profile -notin @('core', 'archviz', 'full') -or $Port -lt 1 -or $Port -gt 65535) { throw 'Invalid setup options.' }
    if (-not [IO.Path]::IsPathRooted($NodePath) -or -not [IO.Path]::IsPathRooted($ServerPath)) { throw 'Setup requires absolute runtime paths.' }
    $environment = [ordered]@{ MAX_ULTRA_MCP_TOOL_PROFILE = $Profile }
    if ($Port -ne 47635) { $environment.MAX_ULTRA_MCP_PORT = [string]$Port }
    return [ordered]@{ mcpServers = [ordered]@{ 'max-ultra-mcp' = [ordered]@{
        command = [IO.Path]::GetFullPath($NodePath)
        args = @([IO.Path]::GetFullPath($ServerPath), '--stdio')
        env = $environment
    } } } | ConvertTo-Json -Depth 8
}

function Get-AntigravityStatus {
    param(
        [string]$NodePath, [string]$ServerPath, [string]$Profile = 'archviz', [int]$Port = 47635,
        [string]$UserProfilePath = $env:USERPROFILE,
        [string]$LocalAppDataPath = $env:LOCALAPPDATA,
        [string[]]$ProgramRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
    )
    $status = [ordered]@{
        installed = 'false'; configured = 'false'; connection = 'unverified'; state = 'cli_missing'
        version = ''; executable = ''; configPath = ''; setupBase64 = ''; configExists = 'false'; setupAvailable = 'false'
        detail = 'Antigravity was not found. Install it, then refresh status.'
    }
    $candidates = @()
    if ($LocalAppDataPath) { $candidates += Join-Path $LocalAppDataPath 'Programs\antigravity\Antigravity.exe' }
    foreach ($programRoot in $ProgramRoots) {
        if ($programRoot) { $candidates += Join-Path $programRoot 'Antigravity\Antigravity.exe' }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $status.installed = 'true'
            $status.executable = $candidate
            $status.state = 'not_configured'
            $status.detail = 'Installed. Select Antigravity and click Install selected.'
            $status.setupAvailable = 'true'
            try { $status.version = [string](Get-Item -LiteralPath $candidate).VersionInfo.ProductVersion } catch { }
            break
        }
    }
    if (-not $UserProfilePath) {
        $status.state = 'check_failed'
        $status.detail = 'The user settings location is unavailable.'
        return $status
    }
    $status.configPath = Join-Path $UserProfilePath '.gemini\config\mcp_config.json'
    if ($status.version -match '^(\d+)\.' -and [int]$Matches[1] -lt 2) {
        $status.setupAvailable = 'false'
        $status.state = 'check_failed'
        $status.detail = 'Automatic setup requires Antigravity 2 or later. Update Antigravity and refresh status.'
        return $status
    }
    if ($NodePath -and (Test-Path -LiteralPath $NodePath -PathType Leaf) -and (Test-Path -LiteralPath $ServerPath -PathType Leaf)) {
        $setupJson = New-AntigravityConfiguration $NodePath $ServerPath $Profile $Port
        $status.setupBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($setupJson))
    }
    try {
        if (-not (Test-Path -LiteralPath $status.configPath -PathType Leaf)) { return $status }
        $status.configExists = 'true'
        if ((Get-Item -LiteralPath $status.configPath).Length -gt 1048576) { throw 'Settings are too large.' }
        $rawConfig = [IO.File]::ReadAllText($status.configPath)
        if ([string]::IsNullOrWhiteSpace($rawConfig)) { return $status }
        if (-not $rawConfig.TrimStart().StartsWith('{')) { throw 'Settings must be an object.' }
        $config = $rawConfig | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $config -or $config -isnot [PSCustomObject]) { throw 'Invalid settings object.' }
        if ($null -ne $config.PSObject.Properties['mcpServers'] -and $config.mcpServers -isnot [PSCustomObject]) { throw 'Invalid servers object.' }
        $servers = Get-AntigravityProperty $config 'mcpServers'
        if ($null -ne $servers -and $servers -isnot [PSCustomObject]) { throw 'Invalid servers object.' }
        $entry = Get-AntigravityProperty $servers 'max-ultra-mcp'
        if ($null -eq $entry) { return $status }
        $status.state = 'not_configured'
        $status.detail = 'Saved settings need updating. Select Antigravity and click Install selected.'
        $command = Get-AntigravityProperty $entry 'command' ''
        $arguments = @(Get-AntigravityProperty $entry 'args' @())
        $environment = Get-AntigravityProperty $entry 'env'
        if ((Get-AntigravityProperty $entry 'disabled' $false) -ne $false) {
            $status.detail = 'The server is disabled in Antigravity. Enable it and refresh.'
            return $status
        }
        if ($command -isnot [string] -or -not [IO.Path]::IsPathRooted($command) -or $arguments.Count -ne 2) { return $status }
        if ($arguments[0] -isnot [string] -or -not [IO.Path]::IsPathRooted($arguments[0]) -or $arguments[1] -cne '--stdio') { return $status }
        if (-not $NodePath -or [IO.Path]::GetFullPath($command) -ine [IO.Path]::GetFullPath($NodePath) -or [IO.Path]::GetFullPath($arguments[0]) -ine [IO.Path]::GetFullPath($ServerPath)) { return $status }
        if ((Get-AntigravityProperty $environment 'MAX_ULTRA_MCP_TOOL_PROFILE' 'archviz') -cne $Profile -or
            [string](Get-AntigravityProperty $environment 'MAX_ULTRA_MCP_PORT' '47635') -ne [string]$Port -or
            (Get-AntigravityProperty $environment 'MAX_ULTRA_MCP_HOST' '127.0.0.1') -ne '127.0.0.1') { return $status }
        foreach ($override in @('MAX_ULTRA_MCP_TOKEN_FILE', 'MAX_ULTRA_MCP_CONTROL_TOKEN', 'LOCALAPPDATA')) {
            if ($null -ne (Get-AntigravityProperty $environment $override)) { return $status }
        }
        if ((Get-AntigravityProperty $entry 'serverUrl') -or @(Get-AntigravityProperty $entry 'disabledTools' @()).Count -gt 0) { return $status }
        if ($status.setupBase64 -eq '') { $status.state = 'runtime_missing'; return $status }
        $status.configured = 'true'
        $status.state = 'configured'
        $status.detail = 'Settings match. Refresh Antigravity, then run the Test prompt. Connection not verified.'
    } catch {
        $status.state = 'check_failed'
        $status.detail = 'Could not read valid Antigravity settings. Review the file and refresh status.'
    }
    return $status
}
