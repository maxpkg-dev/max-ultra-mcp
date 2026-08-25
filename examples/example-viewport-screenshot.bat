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
echo   Every run overwrites the same viewport-current.png file.
echo   The scene is not changed or saved.
echo.

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\scripts\run-node-script.ps1" "examples\example-viewport-screenshot\example-viewport-screenshot.js"
set "EXAMPLE_EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXAMPLE_EXIT_CODE%"=="0" (echo   Status: COMPLETE) else (echo   Status: NOT RUN)
echo.
echo   Press any key to close this window.
pause >nul
exit /b %EXAMPLE_EXIT_CODE%
