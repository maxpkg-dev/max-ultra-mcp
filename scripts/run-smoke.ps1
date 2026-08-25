# Runs the dependency-free Max Ultra MCP smoke test through the shared Node.js runner.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

& (Join-Path $PSScriptRoot 'run-node-script.ps1') 'core\smoke-test.js' @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot 'run-node-script.ps1') 'core\v1-smoke-test.js' @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot 'run-node-script.ps1') 'core\cli-integration-test.js' @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
exit 0
