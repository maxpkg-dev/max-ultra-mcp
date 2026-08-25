@rem Runs the detached, ownership-verified Max Ultra MCP shutdown helper.
@rem Copyright (c) 2026 Lukianenko Vasyl
@rem Project website: https://3dground.net
@rem Developed by Lukianenko Vasyl
@echo off
setlocal EnableExtensions
set "BRIDGE_SCRIPT_DIR=%~dp0"

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%BRIDGE_SCRIPT_DIR%stop-owned-server.ps1" %*
exit /b %ERRORLEVEL%