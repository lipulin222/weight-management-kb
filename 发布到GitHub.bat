@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo.
echo   ===== 发布减重科普知识库到 GitHub =====
echo   同一个仓库、同一个目录：索引页 + 编辑页 + 12 篇内容页 + 规范与文案稿
echo.

set VIS=
set /p VIS=  仓库公开还是私有？公开能用 GitHub Pages 在线翻看（y=公开 / 回车=私有）:
if /i "%VIS%"=="y" ( set VISFLAG=--public ) else ( set VISFLAG=--private )

gh auth status >nul 2>&1
if errorlevel 1 (
  echo.
  echo   还没登录 GitHub，接下来打开浏览器让你授权一次...
  gh auth login --hostname github.com --git-protocol https --web
  if errorlevel 1 (
    echo   登录失败或被取消，请重跑本文件。
    pause
    exit /b 1
  )
)

git add -A
git -c core.quotepath=false commit -m "内容更新 %DATE% %TIME%" 2>nul

gh repo view weight-management-kb >nul 2>&1
if errorlevel 1 (
  echo   正在新建仓库并推送...
  gh repo create weight-management-kb %VISFLAG% --source . --remote origin --push
) else (
  echo   仓库已存在，直接推送...
  git push -u origin main
)

echo.
echo   完成。窗口可关闭。
pause
