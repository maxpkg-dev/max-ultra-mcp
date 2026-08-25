# Discovers a supported Node.js runtime and safely runs one project script.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

param(
    [string]$ScriptPath
)

if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    [Console]::Error.WriteLine('[3D Ground | Max Ultra MCP] ERROR | A Node.js script path is required.')
    exit 1
}

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
try {
    if ([System.IO.Path]::IsPathRooted($ScriptPath)) {
        $resolvedScriptPath = [System.IO.Path]::GetFullPath($ScriptPath)
    }
    else {
        $resolvedScriptPath = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $ScriptPath))
    }
}
catch {
    [Console]::Error.WriteLine("[3D Ground | Max Ultra MCP] ERROR | Invalid Node.js script path: $ScriptPath")
    exit 1
}

if (-not (Test-Path -LiteralPath $resolvedScriptPath -PathType Leaf)) {
    [Console]::Error.WriteLine("[3D Ground | Max Ultra MCP] ERROR | Node.js script was not found: $resolvedScriptPath")
    exit 1
}

$supportedExtensions = @('.js', '.cjs', '.mjs')
if ($supportedExtensions -notcontains [System.IO.Path]::GetExtension($resolvedScriptPath).ToLowerInvariant()) {
    [Console]::Error.WriteLine("[3D Ground | Max Ultra MCP] ERROR | Expected a .js, .cjs, or .mjs script: $resolvedScriptPath")
    exit 1
}

$nodeCandidates = @()
$nodeCommands = Get-Command node -CommandType Application -ErrorAction SilentlyContinue
foreach ($nodeCommand in $nodeCommands) {
    if ($nodeCommand.Source) {
        $nodeCandidates += $nodeCommand.Source
    }
}
if ($env:USERPROFILE) {
    $nodeCandidates += Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
}

$nodeExecutable = $null
foreach ($candidatePath in ($nodeCandidates | Select-Object -Unique)) {
    if (-not $candidatePath -or -not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
        continue
    }
    try {
        $candidateVersionText = & $candidatePath -p 'process.versions.node' 2>$null
        $candidateVersion = [Version]($candidateVersionText | Select-Object -First 1)
        if ($candidateVersion.Major -ge 18) {
            $nodeExecutable = $candidatePath
            break
        }
    }
    catch {
        continue
    }
}

if (-not $nodeExecutable) {
    [Console]::Error.WriteLine('[3D Ground | Max Ultra MCP] ERROR | Node.js 18 or newer was not found.')
    [Console]::Error.WriteLine('Install Node.js 18+ or run Max Ultra MCP from a Codex installation with its bundled runtime.')
    exit 1
}

$scriptArguments = @($args)
if ($env:MAX_ULTRA_MCP_OWNER_FILE -and $env:MAX_ULTRA_MCP_OWNER_TOKEN) {
    try {
        $runnerProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction Stop
        $launcherProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($runnerProcess.ParentProcessId)" -ErrorAction Stop
        $env:MAX_ULTRA_MCP_LAUNCHER_PID = [string]$launcherProcess.ProcessId
        $env:MAX_ULTRA_MCP_LAUNCHER_STARTED_AT_UTC = $launcherProcess.CreationDate.ToUniversalTime().ToString('o')
    }
    catch {
        [Console]::Error.WriteLine("[3D Ground | Max Ultra MCP] WARNING | Could not capture launcher ownership metadata: $($_.Exception.Message)")
        $env:MAX_ULTRA_MCP_LAUNCHER_PID = ''
        $env:MAX_ULTRA_MCP_LAUNCHER_STARTED_AT_UTC = ''
    }
}
try {
    & $nodeExecutable $resolvedScriptPath @scriptArguments
    $nodeExitCode = $LASTEXITCODE
}
catch {
    [Console]::Error.WriteLine("[3D Ground | Max Ultra MCP] ERROR | Could not start Node.js: $($_.Exception.Message)")
    exit 1
}

exit $nodeExitCode
