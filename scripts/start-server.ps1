# Starts the 3DGROUND Max Ultra MCP core server through the shared Node.js runner.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

& (Join-Path $PSScriptRoot 'run-node-script.ps1') 'core\server.js' @args
exit $LASTEXITCODE
