# Runs the real Max Ultra MCP Box example through the shared Node.js runner.
# Copyright (c) 2026 Lukianenko Vasyl
# Project website: https://3dground.net
# Developed by Lukianenko Vasyl

& (Join-Path $PSScriptRoot '..\scripts\run-node-script.ps1') 'examples\example-create-box.js' @args
exit $LASTEXITCODE
