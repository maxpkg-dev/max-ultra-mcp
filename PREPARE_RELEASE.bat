@rem Prepares the version from version.ini by default; -Version remains an optional override.
@rem It never pushes or publishes.
@rem Copyright (c) 2026 Lukianenko Vasyl
@rem Project website: https://3dground.net
@rem Developed by Lukianenko Vasyl
@echo off
setlocal EnableExtensions
set "MAX_ULTRA_RELEASE_ROOT=%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%MAX_ULTRA_RELEASE_ROOT%scripts\prepare-release.ps1" %*
set "MAX_ULTRA_RELEASE_EXIT=%ERRORLEVEL%"

echo.
if "%MAX_ULTRA_RELEASE_EXIT%"=="0" (
    echo [3DGROUND ^| Max Ultra MCP] Local release preparation completed.
) else (
    echo [3DGROUND ^| Max Ultra MCP] Local release preparation failed with exit code %MAX_ULTRA_RELEASE_EXIT%.
)
echo.
pause
exit /b %MAX_ULTRA_RELEASE_EXIT%
