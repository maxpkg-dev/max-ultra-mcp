@rem Validates and publishes the newest versioned MZP to GitHub Releases.
@rem Copyright (c) 2026 Lukianenko Vasyl
@rem Project website: https://3dground.net
@rem Developed by Lukianenko Vasyl
@echo off
setlocal EnableExtensions
set "MAX_ULTRA_RELEASE_ROOT=%~dp0"

call "%~dp0scripts\resolve-windows-powershell.bat"
if errorlevel 1 exit /b %ERRORLEVEL%
"%MAX_ULTRA_POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%MAX_ULTRA_RELEASE_ROOT%scripts\publish-github-release.ps1" %*
set "MAX_ULTRA_RELEASE_EXIT=%ERRORLEVEL%"

echo.
if "%MAX_ULTRA_RELEASE_EXIT%"=="0" (
    echo [3DGROUND ^| Max Ultra MCP] Release workflow completed.
) else (
    echo [3DGROUND ^| Max Ultra MCP] Release workflow failed with exit code %MAX_ULTRA_RELEASE_EXIT%.
)
echo.
pause
exit /b %MAX_ULTRA_RELEASE_EXIT%
