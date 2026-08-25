@rem Prints detailed read-only information from the sole connected 3ds Max.
@rem Copyright (c) 2026 Lukianenko Vasyl
@rem Project website: https://3dground.net
@rem Developed by Lukianenko Vasyl
@echo off
setlocal EnableExtensions

title 3DGROUND - Max Ultra MCP - Get Max Info
cls
echo ================================================================
echo   3DGROUND ^| MAX ULTRA MCP
echo   READ-ONLY EXAMPLE - GET DETAILED MAX AND SCENE INFO
echo ================================================================
echo.
echo   Reads detailed 3ds Max and scene information without changes.
echo.

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\scripts\run-node-script.ps1" "examples\example-get-max-info\example-get-max-info.js"
set "EXAMPLE_EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXAMPLE_EXIT_CODE%"=="0" (echo   Status: COMPLETE) else (echo   Status: NOT RUN)
echo.
echo   Press any key to close this window.
pause >nul
exit /b %EXAMPLE_EXIT_CODE%
