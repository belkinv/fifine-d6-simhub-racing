@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Verify.ps1"
set "VERIFY_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %VERIFY_EXIT%
