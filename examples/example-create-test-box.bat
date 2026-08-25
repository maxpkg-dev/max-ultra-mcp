@rem Runs the real one-Box Max Ultra MCP example through the shared safe helper.
@rem Copyright (c) 2026 Lukianenko Vasyl
@rem Project website: https://3dground.net
@rem Developed by Lukianenko Vasyl
@echo off
setlocal EnableExtensions

title 3D Ground - Max Ultra MCP - Create Test Box
cls
echo ================================================================
echo   3D GROUND ^| MAX ULTRA MCP
echo   REAL EXAMPLE - CREATE ONE TEST BOX
echo ================================================================
echo.
echo   This sends one MaxScript command through the running bridge.
echo   It creates MaxUltraMCP_TestBox at [0,0,0], size 20 x 20 x 20.
echo   It never saves the scene and refuses if multiple Max instances exist.
echo.
echo ----------------------------------------------------------------

powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0example-create-box.ps1"
set "EXAMPLE_EXIT_CODE=%ERRORLEVEL%"

echo ----------------------------------------------------------------
if "%EXAMPLE_EXIT_CODE%"=="0" (
    echo   Status   : COMPLETE
) else (
    echo   Status   : NOT RUN
    echo   Review the live inventory or error above; no arbitrary scene was chosen.
)
echo.
echo   Press any key to close this window.
pause >nul
exit /b %EXAMPLE_EXIT_CODE%