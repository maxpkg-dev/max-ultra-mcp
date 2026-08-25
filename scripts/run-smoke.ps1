# Locates Node.js and runs the dependency-free Max Ultra MCP smoke test.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

$nodeCandidates = @()
$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCommand) {
    $nodeCandidates += $nodeCommand.Source
}
$nodeCandidates += Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'

$nodeExecutable = $nodeCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $nodeExecutable) {
    [Console]::Error.WriteLine('Max Ultra MCP smoke test requires Node.js 18 or newer. Install Node.js or run it from a Codex installation with its bundled runtime.')
    exit 1
}

$smokeTestPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\core\smoke-test.js'))
& $nodeExecutable $smokeTestPath
exit $LASTEXITCODE
