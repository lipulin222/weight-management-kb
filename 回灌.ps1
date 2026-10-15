# =============================================================
#  回灌.ps1 · 文案稿 → 内容页
#  用法：双击，或在 PowerShell 里 .\回灌.ps1
#  做什么：把 文案稿\*.md 逐篇重建成 HTML 页面，再重建离线编辑器
# =============================================================
param([string]$root = (Split-Path -Parent $MyInvocation.MyCommand.Path))

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Read-Txt($p) { [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }
function Esc($t) { ($t -replace '&', '&amp;') -replace '<', '&lt;' -replace '>', '&gt;' }
function Bold($t) { [regex]::Replace((Esc $t), '\*\*(.+?)\*\*', '<b>$1</b>') }

# 编号前缀 → 页面目录
$DIRS = @{
  'S' = '03-用药前'; 'W' = '01-用药早期'; 'M' = '02-用药中期'
  'R' = '04-复查';   'E' = '05-停药与维持'; 'K' = '06-购前'
  'D' = '07-消费决策'; 'F' = '08-续药'; 'T' = '09-跨科转诊'; 'G' = '10-结营'
}

Write-Host '===== 回灌 =====' -ForegroundColor Cyan

# ---------- 模板样式 ----------
$tpl = Read-Txt (Join-Path $root '00-规范\科普内容页模板.html')
$s = $tpl.IndexOf('<style>') + 7
$style = $tpl.Substring($s, $tpl.IndexOf('</style>') - $s)

# ---------- 逐篇生成 ----------
$meta = [ordered]@{}
$docs = [ordered]@{}
$built = 0

foreach ($f in (Get-ChildItem (Join-Path $root '文案稿') -Filter *.md | Sort-Object Name)) {
  $lines = (Read-Txt $f.FullName) -split "`r?`n"
  $id = ''; $title = ''; $lead = ''; $rev = ''
  $secs = New-Object System.Collections.ArrayList
  $cur = $null; $figNote = ''; $figSec = ''

  foreach ($raw in $lines) {
    $l = $raw.Trim()
    if ($l -match '^#\s+([A-Z]\d\d)\s*·\s*(.+)$') { $id = $Matches[1]; $title = $Matches[2].Trim(); continue }
    if ($l -match '^>\s*导语：(.+)$') { $lead = $Matches[1].Trim(); continue }
    if ($l -match '^>') { $rev = ($l -replace '^>\s*', '').Trim(); continue }
    if ($l -match '^##\s*配图\s*[（(]第\s*(\d+)\s*节[）)]') { $figSec = $Matches[1]; continue }
    if ($l -match '^##\s+(\d+)\s+(.+)$') {
      $cur = @{ n = $Matches[1]; t = $Matches[2].Trim(); items = @() }
      [void]$secs.Add($cur)
      continue
    }
    if ($l -match '^- 图注：(.+)$') { $figNote = $Matches[1].Trim(); continue }
    if ($l -match '^- 画什么：') { continue }
    if ($l -match '^- (.+)$' -and $cur) {
      $txt = $Matches[1].Trim()
      if ($txt -match '^\*\*(.+?)\*\*\s+—\s+(.+)$') { $cur.items += @{ kind = 'item'; nm = $Matches[1]; ds = $Matches[2] } }
      else { $cur.items += @{ kind = 'li'; txt = $txt } }
    }
  }
  if (-not $id) { Write-Host "  跳过（无编号）：$($f.Name)" -ForegroundColor DarkYellow; continue }

  $prefix = $id.Substring(0, 1).ToUpper()
  if (-not $DIRS.ContainsKey($prefix)) { Write-Host "  跳过（未知前缀 $prefix）：$($f.Name)" -ForegroundColor DarkYellow; continue }

  $relDir = $DIRS[$prefix]
  $htmlRel = $relDir + '\' + $f.BaseName + '.html'
  $mdRel = '文案稿\' + $f.Name

  # 卡片
  $cards = ''
  foreach ($sec in $secs) {
    $inner = ''
    foreach ($i in $sec.items) {
      if ($i.kind -eq 'li') { $inner += "`n            <li>" + (Bold $i.txt) + "</li>" }
    }
    if ($inner) { $inner = "`n          <ul class=""ck"">" + $inner + "`n          </ul>" }
    foreach ($i in $sec.items) {
      if ($i.kind -eq 'item') {
        $inner += "`n          <div class=""item"">`n            <div class=""nm"">" + (Esc $i.nm) + "</div>`n            <div class=""ds"">" + (Esc $i.ds) + "</div>`n          </div>"
      }
    }
    if ($figNote -and ($figSec -eq $sec.n -or (-not $figSec))) {
      $host2 = Join-Path (Join-Path $root $relDir) ' '
      $oldPage = Join-Path (Join-Path $root $relDir) ($f.BaseName + '.html')
      $svg = ''
      if (Test-Path $oldPage) {
        $m0 = [regex]::Match((Read-Txt $oldPage), '(?s)<figure class="fig">.*?(<svg.*?</svg>)')
        if ($m0.Success) { $svg = ($m0.Groups[1].Value -replace '\s+', ' ').Trim() }
      }
      $img = if ($svg) { '            ' + $svg } else { '            <span class="fig__area" aria-hidden="true"></span>' }
      $inner += "`n        <figure class=""fig"">`n          <span class=""fig__tag"">示意图</span>`n" + $img + "`n          <figcaption class=""fig__cap"">" + (Esc $figNote) + "</figcaption>`n        </figure>"
    }
    $cards += "`n      <!-- ============ " + $sec.n + " ============ -->`n      <div class=""card"">`n        <div class=""sec-h"">`n          <span class=""sec-n"">" + $sec.n + "</span>`n          <span class=""sec-t"">" + (Esc $sec.t) + "</span>`n        </div>" + $inner + "`n      </div>`n"
  }

  $page = @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>$title</title>
<link rel="icon" href="../assets/branding-pic/icon.png">
<style>
$style
</style>
</head>
<body>
<div class="shell">
  <div class="phone">
    <header class="topbar">
      <button class="topbar__back" type="button" onclick="history.back()" aria-label="返回">
        <svg viewBox="0 0 24 24" fill="none"><path d="M15 6L9 12L15 18" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
      </button>
      <div class="topbar__title">科学减重</div>
      <a class="topbar__idx" href="../index.html" aria-label="内容目录">
        <svg viewBox="0 0 24 24" fill="none"><path d="M4 6h16M4 12h16M4 18h11" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>
      </a>
    </header>

    <main class="page">
      <!-- ============ 版头 ============ -->
      <header class="art-hd">
        <span class="art-hd__k">科学减重服务</span>
        <h1 class="art-hd__t">$title</h1>
        <p class="art-hd__lead">$lead</p>
      </header>
$cards
  <!-- ============ 审核与说明（三件套） ============ -->
  <div class="card info">
    <div class="ar__rv"><span class="ar__rv-i">审核</span>$rev</div>
    <p class="disclaim">本篇内容仅供参考，具体情况以你的处方、药品说明书和医生指导为准。</p>
  </div>

  <!-- ============ 吸底问 AI ============ -->
  <div class="askbar">
    <button class="btn" type="button">问 AI 减重助理</button>
  </div>
    </main>
  </div>
</div>

</body>
</html>
"@

  $outDir = Join-Path $root $relDir
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $outDir ($f.BaseName + '.html')), $page, $utf8)

  $meta[$id] = @{ md = $mdRel; html = $htmlRel }
  $docs[$id] = Read-Txt $f.FullName
  $built++
  Write-Host ("  {0}  {1}  →  {2}" -f $id, $title, $htmlRel)
}

# ---------- 目录.json（编辑器用它，不用手改列表） ----------
[System.IO.File]::WriteAllText((Join-Path $root '文案稿\目录.json'), (($meta | ConvertTo-Json -Compress) -replace '\\u003c', '<'), $utf8)

# ---------- 重建离线编辑器 ----------
$figs = [ordered]@{}
foreach ($k in $meta.Keys) {
  $p = Join-Path $root $meta[$k].html
  if (Test-Path $p) {
    $m = [regex]::Match((Read-Txt $p), '(?s)<figure class="fig">.*?(<svg.*?</svg>)')
    if ($m.Success) { $figs[$k] = ($m.Groups[1].Value -replace '\s+', ' ').Trim() }
  }
}

$ed = Read-Txt (Join-Path $root 'editor.html')
$ed = $ed.Replace('const DOCS = { /*__DOCS__*/ };', 'const DOCS = ' + ($docs | ConvertTo-Json -Compress) + ';')
$ed = $ed.Replace("const HEAD = ''; /*__HEAD__*/", 'const HEAD = ' + ($style.Replace('"../assets/', '"assets/') | ConvertTo-Json -Compress) + ';')
$ed = $ed.Replace('const FIGS = { /*__FIGS__*/ };', 'const FIGS = ' + ($figs | ConvertTo-Json -Compress) + ';')
$ed = $ed.Replace('const META = { /*__META__*/ };', 'const META = ' + ($meta | ConvertTo-Json -Compress) + ';')
[System.IO.File]::WriteAllText((Join-Path $root 'editor-offline.html'), $ed, $utf8)

Write-Host '===== 完成 =====' -ForegroundColor Cyan
Write-Host ("页面回灌 {0} 篇 · 插图 {1} 张 · 离线编辑器已重建" -f $built, $figs.Count)
Write-Host '下一步：更新 index.html 的 GROUPS、00-索引清单，再 git push' -ForegroundColor DarkGray
