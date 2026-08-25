# Locates Node.js 18+ and runs the real Max Ultra MCP Box example.
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
    exit 1
}

$examplePath = Join-Path $PSScriptRoot 'example-create-box.js'
& $nodeExecutable $examplePath
exit $LASTEXITCODE