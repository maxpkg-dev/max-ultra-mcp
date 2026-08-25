@rem Starts the branded Max Ultra MCP server console and parses bootstrap launch arguments.
@rem Copyright (c) 2026 Lukianenko Vasyl
@rem Project website: https://3dground.net
@rem Developed by Lukianenko Vasyl
@echo off
setlocal EnableExtensions
set "BRIDGE_SCRIPT_DIR=%~dp0"

set "BRIDGE_NO_PAUSE=0"
set "BRIDGE_PORT_OVERRIDE="
set "BRIDGE_OWNER_FILE="
set "BRIDGE_OWNER_TOKEN="
set "BRIDGE_OWNER_MAX_PID="

:parse_arguments
if "%~1"=="" goto arguments_complete
if /I "%~1"=="--no-pause" set "BRIDGE_NO_PAUSE=1"
if /I "%~1"=="--port" (
    if "%~2"=="" (
        echo [3DGROUND ^| Max Ultra MCP] ERROR ^| --port requires a value.
        exit /b 2
    )
    set "BRIDGE_PORT_OVERRIDE=%~2"
    shift
)
if /I "%~1"=="--owner-file" (
    if "%~2"=="" (
        echo [3DGROUND ^| Max Ultra MCP] ERROR ^| --owner-file requires a value.
        exit /b 2
    )
    set "BRIDGE_OWNER_FILE=%~2"
    shift
)
if /I "%~1"=="--owner-token" (
    if "%~2"=="" (
        echo [3DGROUND ^| Max Ultra MCP] ERROR ^| --owner-token requires a value.
        exit /b 2
    )
    set "BRIDGE_OWNER_TOKEN=%~2"
    shift
)
if /I "%~1"=="--owner-max-pid" (
    if "%~2"=="" (
        echo [3DGROUND ^| Max Ultra MCP] ERROR ^| --owner-max-pid requires a value.
        exit /b 2
    )
    set "BRIDGE_OWNER_MAX_PID=%~2"
    shift
)
shift
goto parse_arguments

:arguments_complete
set "BRIDGE_HOST=%MAX_ULTRA_MCP_HOST%"
if not defined BRIDGE_HOST set "BRIDGE_HOST=127.0.0.1"
set "BRIDGE_PORT=%MAX_ULTRA_MCP_PORT%"
if not defined BRIDGE_PORT set "BRIDGE_PORT=47635"
if defined BRIDGE_PORT_OVERRIDE set "BRIDGE_PORT=%BRIDGE_PORT_OVERRIDE%"
set "MAX_ULTRA_MCP_PORT=%BRIDGE_PORT%"
if defined BRIDGE_OWNER_FILE if not defined BRIDGE_OWNER_TOKEN (
    echo [3DGROUND ^| Max Ultra MCP] ERROR ^| --owner-file and --owner-token must be supplied together.
    exit /b 2
)
if defined BRIDGE_OWNER_TOKEN if not defined BRIDGE_OWNER_FILE (
    echo [3DGROUND ^| Max Ultra MCP] ERROR ^| --owner-file and --owner-token must be supplied together.
    exit /b 2
)
if defined BRIDGE_OWNER_FILE (
    set "MAX_ULTRA_MCP_OWNER_FILE=%BRIDGE_OWNER_FILE%"
    set "MAX_ULTRA_MCP_OWNER_TOKEN=%BRIDGE_OWNER_TOKEN%"
    set "MAX_ULTRA_MCP_OWNER_MAX_PID=%BRIDGE_OWNER_MAX_PID%"
    set "MAX_ULTRA_MCP_LAUNCHER_PATH=%BRIDGE_SCRIPT_DIR%start-server.bat"
)

if "%BRIDGE_NO_PAUSE%"=="0" (
    title 3DGROUND - Max Ultra MCP
    cls
    echo ================================================================
    echo   3DGROUND
    echo   Max Ultra MCP
    echo ================================================================
    echo.
    echo   Status   : STARTING
    echo   Endpoint : %BRIDGE_HOST%:%BRIDGE_PORT%
    echo.
    echo   Keep this window open while agents and 3ds Max use the bridge.
    echo   Run 01_START_MAX_ULTRA_MCP_FIRST.ms in every Max instance.
    echo   Press Ctrl+C to stop the server.
    echo.
    echo ----------------------------------------------------------------
)

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%BRIDGE_SCRIPT_DIR%run-node-script.ps1" "core\server.js" "--daemon"
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
