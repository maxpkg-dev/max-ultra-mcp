@rem Prints a concise read-only scene summary from the sole connected Max.
@rem Copyright (c) 2026 Lukianenko Vasyl
@rem Project website: https://3dground.net
@rem Developed by Lukianenko Vasyl
@echo off
setlocal EnableExtensions

title 3DGROUND - Max Ultra MCP - Scene Summary
cls
echo ================================================================
echo   3DGROUND ^| MAX ULTRA MCP
echo   READ-ONLY EXAMPLE - SCENE SUMMARY
echo ================================================================
echo.
echo   Reads scene statistics and never saves or modifies the scene.
echo.

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\scripts\run-node-script.ps1" "examples\example-scene-summary\example-scene-summary.js"
set "EXAMPLE_EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXAMPLE_EXIT_CODE%"=="0" (echo   Status: COMPLETE) else (echo   Status: NOT RUN)
echo.
echo   Press any key to close this window.
pause >nul
exit /b %EXAMPLE_EXIT_CODE%
