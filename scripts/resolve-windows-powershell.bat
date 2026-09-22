@rem Resolves native Windows PowerShell from Windows directories without PATH lookup.
@rem Copyright (c) 2026 Lukianenko Vasyl
@rem Project website: https://3dground.net
@rem Developed by Lukianenko Vasyl
@echo off
rem Intentionally no setlocal: return the resolved executable to the calling launcher.
set "MAX_ULTRA_POWERSHELL_EXE="
if defined SystemRoot call :resolve_root "%SystemRoot%"
if defined MAX_ULTRA_POWERSHELL_EXE exit /b 0
if defined windir call :resolve_root "%windir%"
if defined MAX_ULTRA_POWERSHELL_EXE exit /b 0
echo [3DGROUND ^| Max Ultra MCP] POWERSHELL_NOT_FOUND: Windows PowerShell was not found in the Windows system directories. Check Windows and SystemRoot/windir; PATH is not used. 1>&2
exit /b 2

:resolve_root
rem Reject empty, relative, and drive-relative roots.
set "MAX_ULTRA_WINDOWS_ROOT=%~1"
if not "%MAX_ULTRA_WINDOWS_ROOT:~1,2%"==":\" exit /b 0
rem Sysnative exists only for a 32-bit process on 64-bit Windows.
call :resolve_executable "%~1\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if defined MAX_ULTRA_POWERSHELL_EXE exit /b 0
call :resolve_executable "%~1\System32\WindowsPowerShell\v1.0\powershell.exe"
exit /b 0

:resolve_executable
rem Inspect the directory attribute instead of probing an executable with a trailing slash.
if not exist "%~1" exit /b 0
set "MAX_ULTRA_POWERSHELL_ATTRIBUTES="
for %%F in ("%~1") do set "MAX_ULTRA_POWERSHELL_ATTRIBUTES=%%~aF"
if not defined MAX_ULTRA_POWERSHELL_ATTRIBUTES exit /b 0
if /i "%MAX_ULTRA_POWERSHELL_ATTRIBUTES:~0,1%"=="d" exit /b 0
set "MAX_ULTRA_POWERSHELL_EXE=%~1"
exit /b 0
