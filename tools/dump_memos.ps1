<#
  dump_memos.ps1 — 備忘錄同步事故診斷（Windows）
  讀 SyncNest 的 memos.json（與 .bak）並列出每則 updatedAt / deleted / sortKey / 文字摘要，
  標示與關鍵門檻的關係，用來判定「舊蓋新」根因。
  詳見 docs/memo-sync-incident-2026-07-06.md。

  用法：
    powershell -ExecutionPolicy Bypass -File tools\dump_memos.ps1
    powershell -ExecutionPolicy Bypass -File tools\dump_memos.ps1 -Path "C:\自訂\SyncNest\memos.json"
#>
param(
  [string]$Path = ""
)

# Mac 目前最新時間戳（2026-07-03 18:40:56，週五）。晚於此=理應是週日的新編輯。
$MAC_MAX = 1783075256890L

function Resolve-MemosPath {
  param([string]$explicit)
  if ($explicit -ne "") { return $explicit }

  # 1) 自訂儲存資料夾：appSupport 的 storage_dir（若有設定過）
  $roaming = [Environment]::GetFolderPath("ApplicationData")
  foreach ($appDir in @("com.philio\syncnest", "com.philio\SyncNest", "syncnest", "SyncNest")) {
    $cfg = Join-Path $roaming (Join-Path $appDir "storage_dir")
    if (Test-Path $cfg) {
      $dir = (Get-Content -Raw -Path $cfg).Trim()
      if ($dir -ne "" -and (Test-Path (Join-Path $dir "memos.json"))) {
        return (Join-Path $dir "memos.json")
      }
    }
  }
  # 2) 預設 Downloads\SyncNest
  $dl = Join-Path ([Environment]::GetFolderPath("UserProfile")) "Downloads\SyncNest\memos.json"
  return $dl
}

function Dump-File {
  param([string]$file)

  Write-Host ("=" * 72)
  Write-Host "檔案: $file"
  if (-not (Test-Path $file)) { Write-Host "  (不存在)"; return }

  $fi = Get-Item $file
  Write-Host ("  檔案修改時間: {0}" -f $fi.LastWriteTime)
  Write-Host ("  大小: {0} bytes" -f $fi.Length)

  try {
    $json = Get-Content -Raw -Path $file | ConvertFrom-Json
  } catch {
    Write-Host "  解析失敗: $($_.Exception.Message)"
    return
  }

  $epoch = [DateTimeOffset]::FromUnixTimeMilliseconds(0)
  $count = 0
  foreach ($m in $json) {
    $count++
    $ua = [int64]$m.updatedAt
    $dt = [DateTimeOffset]::FromUnixTimeMilliseconds($ua).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
    $rel = if ($ua -gt $MAC_MAX) { ">>晚於Mac週五(理應週日,GOOD)" } else { "早於/等於Mac週五" }
    $txt = ""
    if ($m.text) { $txt = ([string]$m.text) }
    if ($txt.Length -gt 24) { $txt = $txt.Substring(0,24) }
    $txt = $txt -replace "`r?`n"," "
    $todoN = 0
    if ($m.todos) { $todoN = @($m.todos).Count }
    Write-Host ("  {0}  ua={1}  del={2}  sort={3}  todos={4}  '{5}'  [{6}]" -f `
      $dt, $ua, $m.deleted, $m.sortKey, $todoN, $txt, $rel)
  }
  Write-Host ("  共 {0} 則" -f $count)
}

$target = Resolve-MemosPath -explicit $Path
Write-Host ("Mac 週五最新時間戳門檻 MAC_MAX = {0}  (2026-07-03 18:40:56)" -f $MAC_MAX)
Write-Host ("現在時間: {0}  (epoch ms = {1})" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())

Dump-File -file $target
Dump-File -file "$target.bak"

Write-Host ("=" * 72)
Write-Host "判讀：找你昨晚(週日)編輯過的那則，看它是 [>>晚於Mac週五] 還是 [早於/等於Mac週五]。"
Write-Host "  - 晚於  => bug 在同步/合併方向"
Write-Host "  - 早於  => bug 在時間戳寫入(漏 bump updatedAt)"
Write-Host "詳見 docs/memo-sync-incident-2026-07-06.md 第六節。"
