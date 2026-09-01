@echo off
rem Launches source-checkout diagnostics for Max Ultra MCP with the bundled runtime or development Node.js.
rem Copyright (c) 2026 Lukianenko Vasyl
rem Project website: https://3dground.net
rem Developed by Lukianenko Vasyl

setlocal
set "MAX_ULTRA_DIAGNOSTICS_ROOT=%~dp0..\"
set "MAX_ULTRA_DIAGNOSTICS_NODE=%MAX_ULTRA_DIAGNOSTICS_ROOT%runtime\win-x64\node.exe"
if exist "%MAX_ULTRA_DIAGNOSTICS_NODE%" goto run_cli
set "MAX_ULTRA_DIAGNOSTICS_NODE=node"

:run_cli
"%MAX_ULTRA_DIAGNOSTICS_NODE%" "%MAX_ULTRA_DIAGNOSTICS_ROOT%core\cli.js" %*
exit /b %ERRORLEVEL%
