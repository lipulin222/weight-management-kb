param(
  [string]$root = (Split-Path -Parent $MyInvocation.MyCommand.Path),
  [int]$port = 8190
)
$ErrorActionPreference = 'Stop'
$enc = [System.Text.Encoding]::UTF8
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-Mime($p) {
  switch -Regex ($p) {
    '\.html$' { 'text/html; charset=utf-8'; break }
    '\.md$'   { 'text/plain; charset=utf-8'; break }
    '\.css$'  { 'text/css; charset=utf-8'; break }
    '\.js$'   { 'application/javascript; charset=utf-8'; break }
    '\.json$' { 'application/json; charset=utf-8'; break }
    '\.svg$'  { 'image/svg+xml'; break }
    '\.png$'  { 'image/png'; break }
    '\.jpg$'  { 'image/jpeg'; break }
    '\.webp$' { 'image/webp'; break }
    '\.woff2$' { 'font/woff2'; break }
    '\.woff$' { 'font/woff'; break }
    '\.otf$'  { 'font/otf'; break }
    '\.ttf$'  { 'font/ttf'; break }
    default   { 'application/octet-stream' }
  }
}
function In-Git([string[]]$gArgs) {
  $prev = Get-Location
  $eap = $ErrorActionPreference
  try {
    Set-Location $root
    $ErrorActionPreference = 'Continue'
    return (& git $gArgs 2>&1 | Out-String).Trim()
  } catch { return '' }
  finally { $ErrorActionPreference = $eap; Set-Location $prev }
}

$started = $false
for ($i = 0; $i -lt 12; $i++) {
  try {
    $tryPort = $port + $i
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $tryPort)
    $listener.Start()
    $port = $tryPort
    $started = $true
    break
  } catch { }
}
if (-not $started) {
  Write-Output "端口都被占用，换一个： .\start-editor.ps1 -port 8300"
  exit 1
}

$url = "http://127.0.0.1:$port/editor.html"
Write-Output ""
Write-Output "  编辑器已启动： $url"
Write-Output "  （请用 127.0.0.1 这个地址，不要写 localhost）"
Write-Output "  目录：$root"
Write-Output "  关掉这个窗口 = 停止服务"
Write-Output ""
try { Start-Process $url | Out-Null } catch { }

while ($true) {
  $client = $null
  try {
    $client = $listener.AcceptTcpClient()
    $ns = $client.GetStream()

    $hms = New-Object System.IO.MemoryStream
    $one = New-Object byte[] 1
    $last4 = New-Object System.Collections.Generic.List[byte]
    while ($true) {
      $n = $ns.Read($one, 0, 1)
      if ($n -le 0) { break }
      $hms.WriteByte($one[0])
      $last4.Add($one[0])
      if ($last4.Count -gt 4) { $last4.RemoveAt(0) }
      if ($last4.Count -eq 4 -and $last4[0] -eq 13 -and $last4[1] -eq 10 -and $last4[2] -eq 13 -and $last4[3] -eq 10) { break }
    }
    $headText = $enc.GetString($hms.ToArray())
    if ([string]::IsNullOrWhiteSpace($headText)) { $client.Close(); continue }

    $hLines = $headText -split "`r`n"
    $reqLine = $hLines[0]
    $cl = 0
    foreach ($hl in $hLines) { if ($hl -match '^Content-Length:\s*(\d+)') { $cl = [int]$Matches[1] } }
    $body = ''
    if ($cl -gt 0) {
      $bodyMs = New-Object System.IO.MemoryStream
      $need = $cl
      while ($need -gt 0) {
        $sz = [Math]::Min(4096, $need)
        $buf = New-Object byte[] $sz
        $n = $ns.Read($buf, 0, $sz)
        if ($n -le 0) { break }
        $bodyMs.Write($buf, 0, $n)
        $need -= $n
      }
      $body = $enc.GetString($bodyMs.ToArray())
    }

    $parts = $reqLine.Split(' ')
    $method = $parts[0]
    $urlPath = [System.Uri]::UnescapeDataString($parts[1])
    $pathOnly = $urlPath.Split('?')[0]
    $query = if ($urlPath.Contains('?')) { $urlPath.Split('?')[1] } else { '' }

    $status = '200 OK'
    $ctype = 'text/plain; charset=utf-8'
    $payloadBytes = $null

    if ($pathOnly -eq '/api/md' -or $pathOnly -eq '/api/page') {
      $f = ''
      foreach ($q in ($query -split '&')) { if ($q -like 'file=*') { $f = $q.Substring(5) } }
      $full = Join-Path $root $f
      if ($method -eq 'GET' -and $pathOnly -eq '/api/md') {
        if (Test-Path $full) { $payloadBytes = [System.IO.File]::ReadAllBytes($full); $ctype = 'text/plain; charset=utf-8' }
        else { $status = '404 Not Found'; $payloadBytes = $enc.GetBytes('文案稿不存在：' + $f) }
      } else {
        $dir = Split-Path $full -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        [System.IO.File]::WriteAllText($full, $body, $utf8NoBom)
        $payloadBytes = $enc.GetBytes((ConvertTo-Json -Compress @{ ok = $true; file = $f }))
        $ctype = 'application/json; charset=utf-8'
      }
    }
    elseif ($pathOnly -eq '/api/status') {
      $inside = In-Git @('rev-parse', '--is-inside-work-tree')
      $info = @{ repo = ''; branch = ''; remote = '' }
      if ($inside -eq 'true') {
        $info.repo = Split-Path $root -Leaf
        $info.branch = In-Git @('rev-parse', '--abbrev-ref', 'HEAD')
        $info.remote = In-Git @('remote', 'get-url', 'origin')
      } else { $info.repo = '未初始化' }
      $payloadBytes = $enc.GetBytes((ConvertTo-Json -Compress $info))
      $ctype = 'application/json; charset=utf-8'
    }
    elseif ($pathOnly -eq '/api/publish') {
      $log = New-Object System.Collections.Generic.List[string]
      $ok = $true
      try {
        $j = $body | ConvertFrom-Json
        $msg = if ($j.msg) { $j.msg } else { '医学编辑定稿' }
        $f = ''
        foreach ($q in ($query -split '&')) { if ($q -like 'file=*') { $f = $q.Substring(5) } }
        if (-not $f) { $f = '文案稿/文案稿-用药早期与中期-v4.1.md' }
        if ($j.md) {
          $full = Join-Path $root $f
          $dir = Split-Path $full -Parent
          if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
          [System.IO.File]::WriteAllText($full, $j.md, $utf8NoBom)
          $log.Add('已保存文案稿：' + $f)
        }

        $cfgPath = Join-Path $root 'publish.config.json'
        $cfg = $null
        if (Test-Path $cfgPath) { $cfg = (Get-Content -Raw -Encoding UTF8 $cfgPath) | ConvertFrom-Json }
        $branch = if ($cfg -and $cfg.branch) { $cfg.branch } else { 'main' }
        $remote = if ($cfg) { $cfg.remote } else { '' }
        $prefix = if ($cfg -and $cfg.messagePrefix) { $cfg.messagePrefix } else { '科普内容更新' }

        $inside = In-Git @('rev-parse', '--is-inside-work-tree')
        if ($inside -ne 'true') { $log.Add((In-Git @('init', '-b', $branch))); $log.Add('已初始化 git 仓库') }

        if ($remote) {
          $cur = In-Git @('remote', 'get-url', 'origin')
          if ($cur -eq $remote) { $log.Add('远端已配置') }
          elseif ([string]::IsNullOrWhiteSpace($cur) -or $cur -match 'fatal') { In-Git @('remote', 'add', 'origin', $remote) | Out-Null; $log.Add('已添加远端') }
          else { In-Git @('remote', 'set-url', 'origin', $remote) | Out-Null; $log.Add('已更新远端') }
        }

        $commitMsg = $prefix + ' · ' + $msg + ' · ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')
        In-Git @('add', '-A') | Out-Null
        $commitOut = In-Git @('commit', '-m', $commitMsg)
        $log.Add($commitOut)
        if ($commitOut -match 'nothing to commit') { $log.Add('没有内容变化，跳过推送') }
        elseif ($remote) {
          $pushOut = In-Git @('push', '-u', 'origin', $branch)
          $log.Add($pushOut)
          if ($pushOut -match 'fatal|error|rejected|denied') { $ok = $false }
        } else { $log.Add('未配置 remote，只在本机提交（填 publish.config.json 后可推送）') }
      } catch {
        $ok = $false
        $log.Add('异常：' + $_.Exception.Message)
      }
      $payloadBytes = $enc.GetBytes((ConvertTo-Json -Compress @{ ok = $ok; log = ($log -join "`n") }))
      $ctype = 'application/json; charset=utf-8'
    }
    else {
      $rel = $pathOnly.TrimStart('/')
      if ([string]::IsNullOrEmpty($rel)) { $rel = 'editor.html' }
      $full = Join-Path $root $rel
      if ((Test-Path $full) -and -not (Get-Item $full).PSIsContainer) {
        $payloadBytes = [System.IO.File]::ReadAllBytes($full)
        $ctype = Get-Mime $full
      } else {
        $status = '404 Not Found'
        $payloadBytes = $enc.GetBytes('404 ' + $rel)
      }
    }

    $head = "HTTP/1.1 $status`r`nContent-Type: $ctype`r`nContent-Length: $($payloadBytes.Length)`r`nConnection: close`r`n`r`n"
    $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
    $ns.Write($hb, 0, $hb.Length)
    $ns.Write($payloadBytes, 0, $payloadBytes.Length)
    $ns.Flush()
  } catch {
  } finally {
    try { if ($client) { $client.Close() } } catch {}
  }
}
