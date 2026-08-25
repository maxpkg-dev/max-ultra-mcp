@rem Starts the current production render through the MaxScript equivalent of F9.
@rem Copyright (c) 2026 Lukianenko Vasyl
@rem Project website: https://3dground.net
@rem Developed by Lukianenko Vasyl
@echo off
setlocal EnableExtensions

title 3DGROUND - Max Ultra MCP - Press Render
cls
echo ================================================================
echo   3DGROUND ^| MAX ULTRA MCP
echo   REAL EXAMPLE - START THE CURRENT PRODUCTION RENDER
echo ================================================================
echo.
echo   Runs the MaxScript command equivalent to Render / F9.
echo   Uses the current production renderer and render settings.
echo.
choice /C YN /N /M "Start rendering now? [Y/N]: "
if errorlevel 2 exit /b 0

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\scripts\run-node-script.ps1" "examples\example-press-render-button\example-press-render-button.js"
set "EXAMPLE_EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXAMPLE_EXIT_CODE%"=="0" (echo   Status: COMPLETE) else (echo   Status: NOT RUN)
echo.
echo   Press any key to close this window.
pause >nul
exit /b %EXAMPLE_EXIT_CODE%
