param(
  [string]$ConfigDir = (Join-Path $env:USERPROFILE ".config\opencode"),
  [switch]$NoShortcuts,
  [switch]$NoStart,
  [switch]$NoModelPrompt,
  [switch]$Yes,
  [switch]$Force,
  [string]$Repo = "trpamuk/opencode-orchestrator-kit"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$localVersion = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
$api = "https://api.github.com/repos/$Repo/releases/latest"
$release = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "opencode-orchestrator-kit-updater" } -TimeoutSec 30
$tag = [string]$release.tag_name
$version = $tag.TrimStart("v")
if ($localVersion -eq $version -and -not $Force) {
  Write-Host "Zaten guncel: v$version" -ForegroundColor Green
  exit 0
}

$zipAsset = $release.assets | Where-Object { $_.name -like "opencode-orchestrator-kit-v*.zip" } | Select-Object -First 1
$shaAsset = $release.assets | Where-Object { $_.name -like "*.zip.sha256" } | Select-Object -First 1
if (-not $zipAsset) {
  throw "Latest release does not contain a kit ZIP."
}

$temp = Join-Path $env:TEMP ("opencode-orchestrator-kit-update-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $temp | Out-Null
$zip = Join-Path $temp $zipAsset.name
Write-Host "Indiriliyor: v$version" -ForegroundColor Cyan
Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zip -UseBasicParsing -TimeoutSec 180

$expected = $null
if ($shaAsset) {
  $shaResponse = Invoke-WebRequest -Uri $shaAsset.browser_download_url -UseBasicParsing -TimeoutSec 30
  $shaText = if ($shaResponse.Content -is [byte[]]) {
    [Text.Encoding]::UTF8.GetString($shaResponse.Content)
  } else {
    [string]$shaResponse.Content
  }
  $expected = ($shaText.Trim() -split '\s+')[0].ToLower()
}
$actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
if ($expected -and $actual -ne $expected) {
  Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
  throw "SHA256 mismatch. Expected $expected, got $actual."
}
Write-Host "SHA256: $actual" -ForegroundColor DarkGray

if (-not $Yes) {
  $answer = Read-Host "Kurulum baslatilsin mi? [E/h]"
  if ($answer -and $answer -notmatch '^[EeYy]') {
    Write-Host "Iptal edildi." -ForegroundColor Yellow
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
  }
}

$extract = Join-Path $temp "kit"
Expand-Archive -Path $zip -DestinationPath $extract -Force
$installer = Join-Path $extract "install.ps1"
if (-not (Test-Path $installer)) {
  throw "install.ps1 not found in the downloaded ZIP."
}

$installArgs = @(
  "-NoProfile",
  "-ExecutionPolicy", "Bypass",
  "-File", $installer,
  "-ConfigDir", $ConfigDir
)
if ($NoShortcuts) { $installArgs += "-NoShortcuts" }
if ($NoStart) { $installArgs += "-NoStart" }
if ($NoModelPrompt) { $installArgs += "-NoModelPrompt" }

& powershell @installArgs
if ($LASTEXITCODE -ne 0) {
  throw "Installer failed with exit code $LASTEXITCODE."
}

Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "Guncelleme tamamlandi: v$version" -ForegroundColor Green
Write-Host "OpenCode Desktop'i tamamen kapatip yeniden ac."
