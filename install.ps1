param(
  [string]$ConfigDir = (Join-Path $env:USERPROFILE ".config\opencode"),
  [switch]$NoShortcuts,
  [switch]$NoStart,
  [switch]$NoModelPrompt,
  [switch]$ClearModel,
  [switch]$ListModels,
  [string]$Model = "",
  [int]$KeepBackups = 0
)

$ErrorActionPreference = "Stop"

$kitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$configDir = $ConfigDir
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

function Prune-Backups([int]$keep) {
  if ($keep -le 0) { return }
  $backupsDir = Join-Path $configDir "backups"
  if (-not (Test-Path $backupsDir)) { return }
  $backups = @(Get-ChildItem $backupsDir -Directory -Filter "*-orchestrator-kit" -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
  if ($backups.Count -le $keep) { return }
  $keepNames = @{}
  foreach ($item in ($backups | Select-Object -First $keep)) {
    $keepNames[$item.FullName.ToLower()] = $true
  }
  $removed = 0
  foreach ($item in $backups) {
    if ($item.FullName -eq $backupRoot) { continue }
    if ($keepNames.ContainsKey($item.FullName.ToLower())) { continue }
    Remove-Item $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
    $removed++
  }
  if ($removed -gt 0) {
    Write-Host "    eski yedekler temizlendi: $removed (son $keep)" -ForegroundColor DarkGray
  }
}

function Write-Utf8NoBom([string]$path, [string]$text) {
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [IO.File]::WriteAllText($path, $text, $utf8)
}

function Get-OpenCodeService {
  $servicePath = Join-Path $configDir "service.json"
  if (-not (Test-Path $servicePath)) { return $null }
  try {
    $service = Get-Content $servicePath -Raw | ConvertFrom-Json
    if (-not $service.password) { return $null }
    $url = $null
    try {
      $out = & opencode service status 2>$null
      $match = [regex]::Match(($out -join " "), 'https?://[^\s]+')
      if ($match.Success) { $url = $match.Value }
    } catch {
      # OpenCode CLI yoksa varsayilan adres denenir.
    }
    if (-not $url) { $url = "http://127.0.0.1:45278" }
    $auth = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("opencode:" + $service.password))
    return [pscustomobject]@{ Url = $url; Auth = $auth }
  } catch {
    return $null
  }
}

function Get-ModelCatalog($service) {
  if (-not $service) { return $null }
  try {
    $headers = @{ Authorization = $service.Auth }
    $modelsResponse = Invoke-RestMethod -Uri ($service.Url + "/api/model") -Headers $headers -TimeoutSec 10
    $defaultResponse = $null
    try {
      $defaultResponse = Invoke-RestMethod -Uri ($service.Url + "/api/model/default") -Headers $headers -TimeoutSec 10
    } catch {
      $defaultResponse = $null
    }
    $raw = if ($modelsResponse.data) { @($modelsResponse.data) } else { @($modelsResponse) }
    $models = @()
    foreach ($model in $raw) {
      if ($model.enabled -eq $false) { continue }
      $providerID = [string]$model.providerID
      $modelID = [string]$model.modelID
      if (-not $providerID -or -not $modelID) { continue }
      $variants = @()
      if ($model.variants) {
        $variants = @($model.variants | ForEach-Object { [string]$_.id } | Where-Object { $_ })
      }
      $inputs = @()
      if ($model.capabilities.input) { $inputs = @($model.capabilities.input) }
      $models += [pscustomobject]@{
        Id = "$providerID/$modelID"
        Provider = $providerID
        Model = $modelID
        Name = [string]$model.name
        Variants = $variants
        Tools = ($model.capabilities.tools -eq $true)
        Vision = ($inputs -contains "image") -or ($inputs -contains "pdf")
        Context = $model.limit.context
      }
    }
    $defaultModel = $null
    if ($defaultResponse) {
      $defaultData = if ($defaultResponse.data) { $defaultResponse.data } else { $defaultResponse }
      if ($defaultData.providerID -and $defaultData.modelID) {
        $defaultModel = "$($defaultData.providerID)/$($defaultData.modelID)"
      }
    }
    return [pscustomobject]@{ Models = @($models); Default = $defaultModel }
  } catch {
    Write-Host "    Model listesi alinamadi: $($_.Exception.Message)" -ForegroundColor Yellow
    return $null
  }
}

function Select-Model($catalog, [string]$currentModel) {
  if (-not $catalog -or $catalog.Models.Count -eq 0) {
    return [pscustomobject]@{ Action = "keep"; Model = $currentModel }
  }
  Write-Host ""
  Write-Host "Mevcut model: $currentModel" -ForegroundColor DarkGray
  Write-Host "Model secimi:" -ForegroundColor Cyan
  Write-Host "  0) Mevcut modeli koru" -ForegroundColor Gray
  Write-Host "  1) Model listesinden sec" -ForegroundColor Gray
  Write-Host "  2) Model alanini bos birak (OpenCode'da sec)" -ForegroundColor Gray
  $choice = Read-Host "Secim [0]"
  if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "0" }
  if ($choice -eq "0") {
    return [pscustomobject]@{ Action = "keep"; Model = $currentModel }
  }
  if ($choice -eq "2") {
    return [pscustomobject]@{ Action = "clear"; Model = "" }
  }
  if ($choice -ne "1") {
    return [pscustomobject]@{ Action = "keep"; Model = $currentModel }
  }

  $available = @($catalog.Models | Where-Object { $_.Tools })
  if ($available.Count -eq 0) { $available = @($catalog.Models) }
  $flat = @()
  $index = 1
  foreach ($group in ($available | Group-Object Provider | Sort-Object Name)) {
    Write-Host "  [$($group.Name)]" -ForegroundColor DarkCyan
    foreach ($model in $group.Group) {
      $suffix = if ($model.Vision) { " (vision)" } else { "" }
      Write-Host ("    {0,3}) {1}{2}" -f $index, $model.Id, $suffix)
      $flat += $model
      $index++
    }
  }
  $pick = Read-Host "Model numarasi (bos = mevcut)"
  if ([string]::IsNullOrWhiteSpace($pick)) {
    return [pscustomobject]@{ Action = "keep"; Model = $currentModel }
  }
  $number = 0
  if (-not [int]::TryParse($pick, [ref]$number) -or $number -lt 1 -or $number -gt $flat.Count) {
    Write-Host "    Gecersiz secim; mevcut model korunuyor." -ForegroundColor Yellow
    return [pscustomobject]@{ Action = "keep"; Model = $currentModel }
  }
  return [pscustomobject]@{ Action = "set"; Model = $flat[$number - 1].Id }
}

function Set-OpenCodeModel([string]$modelID) {
  $target = Join-Path $configDir "opencode.json"
  if (-not (Test-Path $target)) { return }
  try {
    $config = Get-Content $target -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($modelID)) {
      if ($config.PSObject.Properties.Name -contains "model") {
        $config.PSObject.Properties.Remove("model")
      }
    } else {
      if ($config.PSObject.Properties.Name -contains "model") {
        $config.model = $modelID
      } else {
        $config | Add-Member -NotePropertyName model -NotePropertyValue $modelID
      }
    }
    Write-Utf8NoBom $target ($config | ConvertTo-Json -Depth 100)
  } catch {
    Write-Host "    Model yazilamadi: $($_.Exception.Message)" -ForegroundColor Yellow
  }
}

if ($ListModels) {
  $service = Get-OpenCodeService
  $catalog = Get-ModelCatalog $service
  if (-not $catalog) {
    @{ models = @(); default = $null } | ConvertTo-Json -Compress
    exit 1
  }
  @{ models = $catalog.Models; default = $catalog.Default } | ConvertTo-Json -Depth 6 -Compress
  exit 0
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
    if ($existing.PSObject.Properties.Name -contains "default_agent") {
      $existing.default_agent = $template.default_agent
    } else {
      $existing | Add-Member -NotePropertyName default_agent -NotePropertyValue $template.default_agent
    }
    Write-Utf8NoBom $targetConfig ($existing | ConvertTo-Json -Depth 100)
    Write-Host "    mevcut config korunarak plugin/default agent eklendi; model degistirilmedi." -ForegroundColor Green
  } catch {
    Write-Host "    Mevcut config JSON olarak okunamadi; yeni config ayri dosyaya yazildi." -ForegroundColor Yellow
    Copy-Item (Join-Path $kitRoot "config\opencode.json") (Join-Path $configDir "opencode.kit.json") -Force
  }
} else {
  Copy-Item (Join-Path $kitRoot "config\opencode.json") $targetConfig -Force
  Write-Host "    yeni config yazildi." -ForegroundColor Green
}

Write-Step "Model secimi"
$currentModel = $null
if (Test-Path $targetConfig) {
  try {
    $currentModel = [string](Get-Content $targetConfig -Raw | ConvertFrom-Json).model
  } catch {
    $currentModel = $null
  }
}
if ($ClearModel) {
  Set-OpenCodeModel ""
  Write-Host "    model alani bos birakildi; OpenCode'da secilecek." -ForegroundColor DarkGray
} elseif (-not [string]::IsNullOrWhiteSpace($Model)) {
  if ($Model -notmatch '^[^/\s]+/[^/\s]+$') {
    throw "Model formati gecersiz. Ornek: opencode-go/deepseek-v4.1-flash"
  }
  Set-OpenCodeModel $Model
  Write-Host "    model: $Model" -ForegroundColor Green
} elseif ($NoModelPrompt) {
  if ([string]::IsNullOrWhiteSpace($currentModel)) {
    Write-Host "    UYARI: Model secili degil. OpenCode'da bir provider/model sec." -ForegroundColor Yellow
  } else {
    Write-Host "    mevcut model korunuyor: $currentModel" -ForegroundColor DarkGray
  }
} else {
  $service = Get-OpenCodeService
  $catalog = Get-ModelCatalog $service
  if (-not $catalog) {
    Write-Host "    OpenCode servisi kapali veya model listesi alinamadi." -ForegroundColor Yellow
    Write-Host "    Model secimini OpenCode icinden yapabilirsin." -ForegroundColor DarkGray
    if ([string]::IsNullOrWhiteSpace($currentModel)) {
      Write-Host "    UYARI: Model secili degil." -ForegroundColor Yellow
    }
  } else {
    if (-not [string]::IsNullOrWhiteSpace($catalog.Default)) {
      Write-Host "    varsayilan model: $($catalog.Default)" -ForegroundColor DarkGray
    }
    $selected = Select-Model $catalog $currentModel
    if ($selected.Action -eq "set") {
      Set-OpenCodeModel $selected.Model
      Write-Host "    model: $($selected.Model)" -ForegroundColor Green
    } elseif ($selected.Action -eq "clear") {
      Set-OpenCodeModel ""
      Write-Host "    model alani bos birakildi; OpenCode'da secilecek." -ForegroundColor DarkGray
    } else {
      if ([string]::IsNullOrWhiteSpace($currentModel)) {
        Write-Host "    model secili degil; OpenCode'da secilecek." -ForegroundColor Yellow
      } else {
        Write-Host "    mevcut model korunuyor: $currentModel" -ForegroundColor DarkGray
      }
    }
  }
}

Write-Step "OMO-slim, AGENTS.md ve board guard kuruluyor"
$omoTarget = Join-Path $configDir "oh-my-opencode-slim.json"
$preservedPreset = $null
if (Test-Path $omoTarget) {
  try {
    $existingOmo = Get-Content $omoTarget -Raw | ConvertFrom-Json
    if ($existingOmo.preset -in @("session", "opencode-go")) {
      $preservedPreset = $existingOmo.preset
    }
  } catch {
    # Gecersiz mevcut config kit config'i ile degistirilecek.
  }
}
Copy-Item (Join-Path $kitRoot "config\oh-my-opencode-slim.json") $omoTarget -Force
if ($preservedPreset) {
  $newOmo = Get-Content $omoTarget -Raw | ConvertFrom-Json
  $newOmo.preset = $preservedPreset
  Write-Utf8NoBom $omoTarget ($newOmo | ConvertTo-Json -Depth 100)
  Write-Host "    mevcut OMO preset korundu: $preservedPreset" -ForegroundColor DarkGray
}
Copy-Item (Join-Path $kitRoot "config\AGENTS.md") (Join-Path $configDir "AGENTS.md") -Force
Copy-Item (Join-Path $kitRoot "config\orchestrator_append.md") (Join-Path $omoDir "orchestrator_append.md") -Force
Copy-Item (Join-Path $kitRoot "plugins\board-guard.js") (Join-Path $pluginsDir "board-guard.js") -Force
Write-Host "    config dosyalari yazildi." -ForegroundColor Green

Write-Step "Ajan Panosu kuruluyor"
$stage = Join-Path $configDir ("agent-board.stage-" + [guid]::NewGuid().ToString("N"))
if (Test-Path $stage) {
  Remove-Item $stage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $kitRoot "agent-board\*") $stage -Recurse -Force

if (-not (Test-Path (Join-Path $stage "server.mjs")) -or -not (Test-Path (Join-Path $stage "index.html"))) {
  throw "Ajan Panosu staging kopyasi eksik. Kurulum durduruldu; mevcut kurulum korunuyor."
}

if (Test-Path (Join-Path $agentBoardDir "guard.log")) {
  Copy-Item (Join-Path $agentBoardDir "guard.log") (Join-Path $stage "guard.log") -Force
}

$defaultConfigDir = Join-Path $env:USERPROFILE ".config\opencode"
if ($configDir -eq $defaultConfigDir) {
  $panelPids = @(Get-NetTCPConnection -LocalPort 43124 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)
  foreach ($panelPid in $panelPids) {
    Stop-Process -Id $panelPid -Force -ErrorAction SilentlyContinue
  }
  Start-Sleep -Milliseconds 300
}

if (Test-Path $agentBoardDir) {
  Remove-Item $agentBoardDir -Recurse -Force
}
Move-Item $stage $agentBoardDir -Force

$startVbs = Join-Path $agentBoardDir "start.vbs"
$vbs = @"
Set sh = CreateObject("WScript.Shell")
sh.Run """$($node.Source)"" ""$agentBoardDir\server.mjs""", 0, False
"@
Set-Content -Path $startVbs -Value $vbs -Encoding ASCII

if (-not $NoShortcuts) {
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
} else {
  Write-Host "    Kisayollar atlandi (NoShortcuts)." -ForegroundColor DarkGray
}

if (-not $NoStart) {
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
} else {
  Write-Host "    Panel baslatma atlandi (NoStart)." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Kurulum tamamlandi." -ForegroundColor Green
Write-Host ""
Write-Host "Sirada:" -ForegroundColor Cyan
Write-Host "1. OpenCode Desktop'i tamamen kapatip yeniden ac."
Write-Host "2. OpenCode'da istedigin provider/model'i sec (OpenCode Go sart degil)."
Write-Host "3. Panel: http://127.0.0.1:43124/"
Write-Host "4. Side panel: Review pane -> yeni browser sekmesi -> ayni URL."
Write-Host "5. Sorun olursa: doctor.cmd"
Write-Host ""
Write-Host "Yedek: $backupRoot" -ForegroundColor DarkGray
Prune-Backups $KeepBackups
