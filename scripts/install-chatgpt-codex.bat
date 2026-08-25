@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-chatgpt-codex.ps1" %*
exit /b %ERRORLEVEL%
