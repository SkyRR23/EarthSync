@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-earthsync.ps1" %*
exit /b %errorlevel%
