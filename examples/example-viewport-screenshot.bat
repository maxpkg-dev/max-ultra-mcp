@rem Maximizes the active 3ds Max viewport and opens the resulting PNG.
@rem Copyright (c) 2026 Lukianenko Vasyl
@rem Project website: https://3dground.net
@rem Developed by Lukianenko Vasyl
@echo off
setlocal EnableExtensions

title 3DGROUND - Max Ultra MCP - Viewport Screenshot
cls
echo ================================================================
echo   3DGROUND ^| MAX ULTRA MCP
echo   REAL EXAMPLE - MAXIMIZE, CAPTURE, AND OPEN THE VIEWPORT
echo ================================================================
echo.
echo   Maximizes the active viewport, saves a temporary PNG, and opens it.
echo   If the viewport is already maximized, it remains maximized.
echo   The PNG is deleted automatically when this BAT window closes.
echo   The scene is not changed or saved.
echo.

set "MAX_ULTRA_MCP_EXAMPLE_SCREENSHOT_FILE=%TEMP%\3DGROUND-Max-Ultra-MCP-Examples\viewport-%RANDOM%-%RANDOM%.png"
for /f "delims=" %%P in ('powershell.exe -NoLogo -NoProfile -NonInteractive -Command "(Get-CimInstance Win32_Process -Filter ('ProcessId=' + $PID)).ParentProcessId"') do set "MAX_ULTRA_MCP_EXAMPLE_BAT_PID=%%P"

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\scripts\run-node-script.ps1" "examples\example-viewport-screenshot\example-viewport-screenshot.js"
set "EXAMPLE_EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXAMPLE_EXIT_CODE%"=="0" (echo   Status: COMPLETE) else (echo   Status: NOT RUN)
echo.
echo   Press any key to close this window.
pause >nul
del /f /q "%MAX_ULTRA_MCP_EXAMPLE_SCREENSHOT_FILE%" >nul 2>&1
exit /b %EXAMPLE_EXIT_CODE%
