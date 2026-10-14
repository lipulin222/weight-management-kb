@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo.
echo   Starting editor... (keep this window open)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\start-editor.ps1"
echo.
echo   Stopped.
pause
