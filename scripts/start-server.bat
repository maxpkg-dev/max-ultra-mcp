@rem Starts the branded Max Ultra MCP server console and parses bootstrap launch arguments.
@rem Copyright (c) 2026 Lukianenko Vasyl
@rem Project website: https://3dground.net
@rem Developed by Lukianenko Vasyl
@echo off
setlocal EnableExtensions

set "BRIDGE_NO_PAUSE=0"
set "BRIDGE_PORT_OVERRIDE="

:parse_arguments
if "%~1"=="" goto arguments_complete
if /I "%~1"=="--no-pause" set "BRIDGE_NO_PAUSE=1"
if /I "%~1"=="--port" (
    if "%~2"=="" (
        echo [3D Ground ^| Max Ultra MCP] ERROR ^| --port requires a value.
        exit /b 2
    )
    set "BRIDGE_PORT_OVERRIDE=%~2"
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
    echo   Keep this window open while agents and 3ds Max use the bridge.
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