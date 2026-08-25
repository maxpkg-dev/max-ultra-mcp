@echo off
setlocal EnableExtensions

set "BRIDGE_NO_PAUSE=0"
if /I "%~1"=="--no-pause" set "BRIDGE_NO_PAUSE=1"

set "BRIDGE_HOST=%MAX_ULTRA_MCP_HOST%"
if not defined BRIDGE_HOST set "BRIDGE_HOST=127.0.0.1"
set "BRIDGE_PORT=%MAX_ULTRA_MCP_PORT%"
if not defined BRIDGE_PORT set "BRIDGE_PORT=47635"

if "%BRIDGE_NO_PAUSE%"=="0" (
    title 3D Ground - Max Ultra MCP
    cls
    echo ================================================================
    echo   3D GROUND
    echo   Max Ultra MCP
    echo ================================================================
    echo.
    echo   Status   : STARTING
    echo   Endpoint : %BRIDGE_HOST%:%BRIDGE_PORT%
    echo.
    echo   Keep this window open while Codex and 3ds Max use the bridge.
    echo   Run 01_START_MAX_ULTRA_MCP_FIRST.ms in every Max instance.
    echo   Press Ctrl+C to stop the server.
    echo.
    echo ----------------------------------------------------------------
)

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0start-server.ps1"
set "BRIDGE_EXIT_CODE=%ERRORLEVEL%"

if "%BRIDGE_NO_PAUSE%"=="1" exit /b %BRIDGE_EXIT_CODE%

echo ----------------------------------------------------------------
echo.
if "%BRIDGE_EXIT_CODE%"=="0" (
    echo   Status   : STOPPED
) else (
    echo   ERROR    : Max Ultra MCP exited with code %BRIDGE_EXIT_CODE%.
    echo   Review the server message above. No ExecutionPolicy change is needed.
)
echo.
echo   Press any key to close this window.
pause >nul
exit /b %BRIDGE_EXIT_CODE%
