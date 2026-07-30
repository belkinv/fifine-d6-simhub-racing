@echo off
chcp 65001 >nul
title FIFINE D6 / D6-Pro - установка SimHub и сцен
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
set "INSTALL_EXIT=%ERRORLEVEL%"
echo.
if not "%INSTALL_EXIT%"=="0" (
  echo Установка завершилась с ошибкой. Код: %INSTALL_EXIT%
) else (
  echo Установка завершена успешно.
)
echo.
pause
exit /b %INSTALL_EXIT%
