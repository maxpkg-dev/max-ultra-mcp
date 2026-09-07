@rem Registers the source checkout with the official OpenAI client CLI.
@rem Copyright (c) 2026 Lukianenko Vasyl
@rem Project website: https://3dground.net
@rem Developed by Lukianenko Vasyl
@echo off
setlocal
call "%~dp0resolve-windows-powershell.bat"
if errorlevel 1 exit /b %ERRORLEVEL%
"%MAX_ULTRA_POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-chatgpt-codex.ps1" %*
exit /b %ERRORLEVEL%
