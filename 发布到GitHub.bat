@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo.
echo   ===== 发布减重科普知识库到 GitHub =====
echo   仓库名：weight-management-kb（私有）
echo.

gh auth status >nul 2>&1
if errorlevel 1 (
  echo   还没登录 GitHub，接下来会打开浏览器让你授权一次...
  gh auth login --hostname github.com --git-protocol https --web
  if errorlevel 1 (
    echo   登录失败或被取消，请重跑本文件。
    pause
    exit /b 1
  )
)

git add -A
git -c core.quotepath=false commit -m "内容更新 · %DATE% %TIME%" 2>nul

gh repo view weight-management-kb >nul 2>&1
if errorlevel 1 (
  echo   正在新建仓库并推送...
  gh repo create weight-management-kb --private --source . --remote origin --push
) else (
  echo   仓库已存在，直接推送...
  git push -u origin main
)

echo.
echo   完成。窗口可关闭。
pause
