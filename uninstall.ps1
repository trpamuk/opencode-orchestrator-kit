$ErrorActionPreference = "Continue"

$configDir = Join-Path $env:USERPROFILE ".config\opencode"
$startupDir = [Environment]::GetFolderPath("Startup")
$desktopDir = [Environment]::GetFolderPath("Desktop")

Write-Host "Ajan Panosu kaldiriliyor (config dosyalari korunur)." -ForegroundColor Yellow

$pids = @(Get-NetTCPConnection -LocalPort 43124 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)
foreach ($pid in $pids) {
  Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
}

Remove-Item (Join-Path $startupDir "Ajan Panosu.lnk") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $desktopDir "Ajan Panosu.url") -Force -ErrorAction SilentlyContinue

Write-Host "Startup ve masaustu kisayollari kaldirildi." -ForegroundColor Green
Write-Host "Istersen config/agent-board klasorlerini de silebilirsin:" -ForegroundColor DarkGray
Write-Host "  $configDir\agent-board" -ForegroundColor DarkGray
Write-Host "  $configDir\plugins\board-guard.js" -ForegroundColor DarkGray
