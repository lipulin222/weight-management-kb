@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo.
echo   ===== 发布减重科普知识库到 GitHub =====
echo   仓库：lipulin222/weight-management-kb
echo   通道：SSH（git@github.com，22 端口）—— 本机 key 已验证可用
echo   HTTP 443 在本机被阻断，不走 https
echo.

git remote remove origin >nul 2>&1
git remote add origin git@github.com:lipulin222/weight-management-kb.git

git add -A
git -c core.quotepath=false commit -m "内容更新 %DATE% %TIME%" 2>nul

echo   正在推送...
git push -u origin main
if errorlevel 1 (
  echo.
  echo   推送失败。最常见的原因：GitHub 上还没有这个空仓库。
  echo   处理：在 GitHub 网页 / App 里新建空仓库 weight-management-kb，
  echo        不要勾选 README / .gitignore / License，建好后重跑本文件。
  echo.
  echo   若想用 gh CLI 自动建仓，先跑 gh auth login（需要 github.com 443 可达）。
  pause
  exit /b 1
)

echo.
echo   推送完成。窗口可关闭。
pause
