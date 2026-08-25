# Runs the dependency-free Max Ultra MCP smoke test through the shared Node.js runner.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

& (Join-Path $PSScriptRoot 'run-node-script.ps1') 'core\smoke-test.js' @args
exit $LASTEXITCODE
