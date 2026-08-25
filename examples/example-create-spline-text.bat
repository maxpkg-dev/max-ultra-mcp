@rem Creates a visible 3DGROUND - Max Ultra MCP spline text object in the sole connected Max scene.
@rem Copyright (c) 2026 Lukianenko Vasyl
@rem Project website: https://3dground.net
@rem Developed by Lukianenko Vasyl
@echo off
setlocal EnableExtensions

title 3DGROUND - Max Ultra MCP - Create Spline Text
cls
echo ================================================================
echo   3DGROUND ^| MAX ULTRA MCP
echo   REAL EXAMPLE - CREATE SPLINE TEXT IN THE VIEWPORT
echo ================================================================
echo.
echo   Creates an extruded "3DGROUND - Max Ultra MCP" Text shape.
echo   Selects and frames it in the active viewport. Never saves the scene.
echo   Refuses to overwrite an existing MaxUltraMCP_Title object.
echo.

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\scripts\run-node-script.ps1" "examples\example-create-spline-text\example-create-spline-text.js"
set "EXAMPLE_EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXAMPLE_EXIT_CODE%"=="0" (echo   Status: COMPLETE) else (echo   Status: NOT RUN)
echo.
echo   Press any key to close this window.
pause >nul
exit /b %EXAMPLE_EXIT_CODE%
