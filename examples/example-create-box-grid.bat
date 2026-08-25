@rem Creates three clearly named test boxes in the sole connected Max scene.
@rem Copyright (c) 2026 Lukianenko Vasyl
@rem Project website: https://3dground.net
@rem Developed by Lukianenko Vasyl
@echo off
setlocal EnableExtensions

title 3DGROUND - Max Ultra MCP - Create Box Grid
cls
echo ================================================================
echo   3DGROUND ^| MAX ULTRA MCP
echo   REAL EXAMPLE - CREATE THREE TEST BOXES
echo ================================================================
echo.
echo   Creates MaxUltraMCP_GridBox_01 through _03 and never saves.
echo   Refuses before creating anything if any exact name already exists.
echo.

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\scripts\run-node-script.ps1" "examples\example-create-box-grid\example-create-box-grid.js"
set "EXAMPLE_EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXAMPLE_EXIT_CODE%"=="0" (echo   Status: COMPLETE) else (echo   Status: NOT RUN)
echo.
echo   Press any key to close this window.
pause >nul
exit /b %EXAMPLE_EXIT_CODE%
