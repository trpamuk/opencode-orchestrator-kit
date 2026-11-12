$ErrorActionPreference = "Continue"

$configDir = Join-Path $env:USERPROFILE ".config\opencode"
$agentBoardDir = Join-Path $configDir "agent-board"
$startupDir = [Environment]::GetFolderPath("Startup")
$desktopDir = [Environment]::GetFolderPath("Desktop")
$failed = 0

function Check([string]$name, [bool]$ok, [string]$detail = "") {
  if ($ok) {
    Write-Host ("[OK]   " + $name + $(if ($detail) { " - " + $detail } else { "" })) -ForegroundColor Green
  } else {
    Write-Host ("[FAIL] " + $name + $(if ($detail) { " - " + $detail } else { "" })) -ForegroundColor Red
    $script:failed++
  }
}

Write-Host "OpenCode Orchestrator Kit - doctor" -ForegroundColor Cyan

$node = Get-Command node -ErrorAction SilentlyContinue
Check "Node.js" ([bool]$node) $(if ($node) { $node.Source } else { "https://nodejs.org/" })

$opencode = Get-Command opencode -ErrorAction SilentlyContinue
Check "OpenCode CLI" ([bool]$opencode) $(if ($opencode) { (& opencode --version 2>$null) } else { "PATH'te yok; Desktop ile devam edilebilir" })

Check "opencode.json" (Test-Path (Join-Path $configDir "opencode.json"))
Check "oh-my-opencode-slim.json" (Test-Path (Join-Path $configDir "oh-my-opencode-slim.json"))
Check "AGENTS.md" (Test-Path (Join-Path $configDir "AGENTS.md"))
Check "board-guard.js" (Test-Path (Join-Path $configDir "plugins\board-guard.js"))
Check "agent-board/server.mjs" (Test-Path (Join-Path $agentBoardDir "server.mjs"))
Check "agent-board/index.html" (Test-Path (Join-Path $agentBoardDir "index.html"))

$configPath = Join-Path $configDir "opencode.json"
if (Test-Path $configPath) {
  try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $plugins = @($config.plugins)
    Check "OMO-slim plugin" ($plugins -contains "oh-my-opencode-slim@3.0.7") ($plugins -join ", ")
  } catch {
    Check "opencode.json parse" $false $_.Exception.Message
  }
}

$omoPath = Join-Path $configDir "oh-my-opencode-slim.json"
if (Test-Path $omoPath) {
  try {
    $omo = Get-Content $omoPath -Raw | ConvertFrom-Json
    Check "Companion kapali" ($omo.companion.enabled -eq $false) ("enabled=" + $omo.companion.enabled)
    Check "OMO-slim schema 3.0.7" ($omo.'$schema' -match '3\.0\.7') $omo.'$schema'
    Check "OMO preset" ($omo.preset -in @("session", "opencode-go")) ("preset=" + $omo.preset)
    if ($omo.preset -eq "session") {
      Check "Model bagimsiz" ($omo.stripOrchestratorModel -eq $true) ("stripOrchestratorModel=" + $omo.stripOrchestratorModel)
    }
  } catch {
    Check "oh-my-opencode-slim.json parse" $false $_.Exception.Message
  }
}

try {
  $health = Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:43124/health" -TimeoutSec 5
  Check "Panel health" ($health.StatusCode -eq 200) "http://127.0.0.1:43124/"
} catch {
  Check "Panel health" $false $_.Exception.Message
}

try {
  $setup = Invoke-RestMethod -UseBasicParsing "http://127.0.0.1:43124/api/setup" -TimeoutSec 10
  $modelDetail = if ($setup.hasModel) { $setup.defaultModel } else { "OpenCode'da bir provider/model sec" }
  Check "Varsayilan model" ([bool]$setup.hasModel) $modelDetail
} catch {
  Check "Varsayilan model" $false $_.Exception.Message
}

Check "Startup shortcut" (Test-Path (Join-Path $startupDir "Ajan Panosu.lnk"))
Check "Desktop shortcut" (Test-Path (Join-Path $desktopDir "Ajan Panosu.url"))

$guardLog = Join-Path $agentBoardDir "guard.log"
if (Test-Path $guardLog) {
  $last = Get-Content $guardLog -Tail 1
  Check "Board guard log" $true $last
} else {
  Write-Host "[INFO] Board guard log henuz yok (ilk board yaziminda olusur)." -ForegroundColor DarkGray
}

Write-Host ""
if ($failed -eq 0) {
  Write-Host "Sonuc: sorun gorunmuyor." -ForegroundColor Green
  exit 0
}
Write-Host "Sonuc: $failed kontrol basarisiz." -ForegroundColor Red
exit 1
