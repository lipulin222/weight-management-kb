@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo.
echo   本机工作台已启动，浏览器会自动打开。
echo   这个黑窗口不要关，关了就保存不了。
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\start-editor.ps1"
echo.
echo   Stopped.
pause
