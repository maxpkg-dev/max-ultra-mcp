# Locates Node.js 18+ and starts the 3D Ground Max Ultra MCP core server.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

$nodeCandidates = @()
$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCommand) {
    $nodeCandidates += $nodeCommand.Source
}
$nodeCandidates += Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'

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
    [Console]::Error.WriteLine('Install Node.js 18+ or start the bridge from a Codex installation with its bundled runtime.')
    exit 1
}

$serverPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\core\server.js'))
if (-not (Test-Path -LiteralPath $serverPath -PathType Leaf)) {
    [Console]::Error.WriteLine('[3D Ground | Max Ultra MCP] ERROR | core\server.js was not found.')
    exit 1
}
& $nodeExecutable $serverPath
exit $LASTEXITCODE
