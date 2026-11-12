$ErrorActionPreference = "Stop"

$kitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$configDir = Join-Path $env:USERPROFILE ".config\opencode"
$backupRoot = Join-Path $configDir ("backups\" + (Get-Date -Format "yyyyMMdd-HHmmss") + "-orchestrator-kit")
$agentBoardDir = Join-Path $configDir "agent-board"
$pluginsDir = Join-Path $configDir "plugins"
$omoDir = Join-Path $configDir "oh-my-opencode-slim"
$startupDir = [Environment]::GetFolderPath("Startup")
$desktopDir = [Environment]::GetFolderPath("Desktop")

function Write-Step([string]$text) {
  Write-Host ""
  Write-Host "==> $text" -ForegroundColor Cyan
}

function Backup-File([string]$path) {
  if (Test-Path $path) {
    $relative = $path.Substring($configDir.Length).TrimStart("\")
    $target = Join-Path $backupRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item $path $target -Force
    Write-Host "    yedek: $relative" -ForegroundColor DarkGray
  }
}

Write-Host "OpenCode Orchestrator Kit - kurulum" -ForegroundColor Green
Write-Host "Hedef: $configDir"

Write-Step "Gereksinimler kontrol ediliyor"
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
  throw "Node.js bulunamadi. Node.js 22+ kur: https://nodejs.org/"
}
Write-Host "    Node: $($node.Source)"

$opencode = Get-Command opencode -ErrorAction SilentlyContinue
if ($opencode) {
  Write-Host "    OpenCode CLI: $($opencode.Source)"
} else {
  Write-Host "    OpenCode CLI PATH'te yok. Desktop uzerinden devam edilecek." -ForegroundColor Yellow
}

New-Item -ItemType Directory -Force -Path $configDir, $backupRoot, $pluginsDir, $omoDir | Out-Null

Write-Step "Mevcut dosyalar yedekleniyor"
Backup-File (Join-Path $configDir "opencode.json")
Backup-File (Join-Path $configDir "oh-my-opencode-slim.json")
Backup-File (Join-Path $configDir "AGENTS.md")
Backup-File (Join-Path $omoDir "orchestrator_append.md")
Backup-File (Join-Path $pluginsDir "board-guard.js")
if (Test-Path $agentBoardDir) {
  $agentBackup = Join-Path $backupRoot "agent-board"
  Copy-Item $agentBoardDir $agentBackup -Recurse -Force
  Write-Host "    yedek: agent-board" -ForegroundColor DarkGray
}

Write-Step "OpenCode config birlestiriliyor"
$template = Get-Content (Join-Path $kitRoot "config\opencode.json") -Raw | ConvertFrom-Json
$targetConfig = Join-Path $configDir "opencode.json"
if (Test-Path $targetConfig) {
  try {
    $existing = Get-Content $targetConfig -Raw | ConvertFrom-Json
    $newPlugins = @()
    if ($existing.PSObject.Properties.Name -contains "plugins") {
      $newPlugins = @($existing.plugins)
    }
    $newPlugins += @($template.plugins)
    $newPlugins = @($newPlugins | Select-Object -Unique)
    if ($existing.PSObject.Properties.Name -contains "plugins") {
      $existing.plugins = $newPlugins
    } else {
      $existing | Add-Member -NotePropertyName plugins -NotePropertyValue $newPlugins
    }
    if ($existing.PSObject.Properties.Name -contains "model") {
      $existing.model = $template.model
    } else {
      $existing | Add-Member -NotePropertyName model -NotePropertyValue $template.model
    }
    if ($existing.PSObject.Properties.Name -contains "default_agent") {
      $existing.default_agent = $template.default_agent
    } else {
      $existing | Add-Member -NotePropertyName default_agent -NotePropertyValue $template.default_agent
    }
    $existing | ConvertTo-Json -Depth 100 | Set-Content -Path $targetConfig -Encoding UTF8
    Write-Host "    mevcut config korunarak plugin/model eklendi." -ForegroundColor Green
  } catch {
    Write-Host "    Mevcut config JSON olarak okunamadi; yeni config ayri dosyaya yazildi." -ForegroundColor Yellow
    Copy-Item (Join-Path $kitRoot "config\opencode.json") (Join-Path $configDir "opencode.kit.json") -Force
  }
} else {
  Copy-Item (Join-Path $kitRoot "config\opencode.json") $targetConfig -Force
  Write-Host "    yeni config yazildi." -ForegroundColor Green
}

Write-Step "OMO-slim, AGENTS.md ve board guard kuruluyor"
Copy-Item (Join-Path $kitRoot "config\oh-my-opencode-slim.json") (Join-Path $configDir "oh-my-opencode-slim.json") -Force
Copy-Item (Join-Path $kitRoot "config\AGENTS.md") (Join-Path $configDir "AGENTS.md") -Force
Copy-Item (Join-Path $kitRoot "config\orchestrator_append.md") (Join-Path $omoDir "orchestrator_append.md") -Force
Copy-Item (Join-Path $kitRoot "plugins\board-guard.js") (Join-Path $pluginsDir "board-guard.js") -Force
Write-Host "    config dosyalari yazildi." -ForegroundColor Green

Write-Step "Ajan Panosu kuruluyor"
if (Test-Path $agentBoardDir) {
  Remove-Item $agentBoardDir -Recurse -Force
}
Copy-Item (Join-Path $kitRoot "agent-board") $agentBoardDir -Recurse -Force

$startVbs = Join-Path $agentBoardDir "start.vbs"
$vbs = @"
Set sh = CreateObject("WScript.Shell")
sh.Run """$($node.Source)"" ""$agentBoardDir\server.mjs""", 0, False
"@
Set-Content -Path $startVbs -Value $vbs -Encoding ASCII

$urlShortcut = Join-Path $desktopDir "Ajan Panosu.url"
@"
[InternetShortcut]
URL=http://127.0.0.1:43124/
IconFile=C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe
IconIndex=0
"@ | Set-Content -Path $urlShortcut -Encoding ASCII

$ws = New-Object -ComObject WScript.Shell
$lnkPath = Join-Path $startupDir "Ajan Panosu.lnk"
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = "$env:WINDIR\System32\wscript.exe"
$lnk.Arguments = '"' + $startVbs + '"'
$lnk.WorkingDirectory = $agentBoardDir
$lnk.WindowStyle = 7
$lnk.Description = "Ajan Panosu yerel sunucusu"
$lnk.Save()
Write-Host "    Startup: $lnkPath" -ForegroundColor Green

Write-Step "Panel baslatiliyor"
Start-Process -FilePath "$env:WINDIR\System32\wscript.exe" -ArgumentList ('"' + $startVbs + '"') -WindowStyle Hidden
$ready = $false
for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep -Milliseconds 500
  try {
    $health = Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:43124/health" -TimeoutSec 2
    if ($health.StatusCode -eq 200) { $ready = $true; break }
  } catch {}
}
if ($ready) {
  Write-Host "    Panel hazir: http://127.0.0.1:43124/" -ForegroundColor Green
} else {
  Write-Host "    Panel henuz yanit vermedi. start.vbs dosyasini calistirip tekrar dene." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Kurulum tamamlandi." -ForegroundColor Green
Write-Host ""
Write-Host "Sirada:" -ForegroundColor Cyan
Write-Host "1. OpenCode Desktop'i tamamen kapatip yeniden ac."
Write-Host "2. OpenCode Go hesabina gir (yoksa OpenCode auth/login)."
Write-Host "3. Panel: http://127.0.0.1:43124/"
Write-Host "4. Side panel: Review pane -> yeni browser sekmesi -> ayni URL."
Write-Host "5. Sorun olursa: doctor.cmd"
Write-Host ""
Write-Host "Yedek: $backupRoot" -ForegroundColor DarkGray
