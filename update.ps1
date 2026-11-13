param(
  [string]$ConfigDir = (Join-Path $env:USERPROFILE ".config\opencode"),
  [switch]$NoShortcuts,
  [switch]$NoStart,
  [switch]$NoModelPrompt,
  [switch]$Yes,
  [switch]$Force,
  [switch]$CheckOnly,
  [Alias("Version")][string]$RequestedVersion = "",
  [string]$Repo = "trpamuk/opencode-orchestrator-kit"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$localVersion = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
$requested = $RequestedVersion.Trim()
if ($requested.StartsWith("v")) {
  $requested = $requested.Substring(1)
}
$api = if ($requested) {
  "https://api.github.com/repos/$Repo/releases/tags/v$requested"
} else {
  "https://api.github.com/repos/$Repo/releases/latest"
}
try {
  $release = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "opencode-orchestrator-kit-updater" } -TimeoutSec 30
} catch {
  $label = if ($requested) { "v$requested" } else { "latest" }
  throw "Release bulunamadi ($label): $($_.Exception.Message)"
}
$tag = [string]$release.tag_name
$version = $tag.TrimStart("v")
if ($requested -and $version -ne $requested) {
  throw "Requested v$requested but GitHub returned v$version."
}
if ($CheckOnly) {
  Write-Host "Mevcut: v$localVersion"
  Write-Host "Hedef: v$version"
  if ($localVersion -eq $version) {
    Write-Host "Zaten guncel." -ForegroundColor Green
  } else {
    Write-Host "Guncelleme mevcut: v$localVersion -> v$version" -ForegroundColor Yellow
  }
  Write-Host "Release: $($release.html_url)" -ForegroundColor DarkGray
  exit 0
}
if ($localVersion -eq $version -and -not $Force) {
  Write-Host "Zaten guncel: v$version" -ForegroundColor Green
  exit 0
}

$zipAsset = $release.assets | Where-Object { $_.name -like "opencode-orchestrator-kit-v*.zip" } | Select-Object -First 1
$shaAsset = $release.assets | Where-Object { $_.name -like "*.zip.sha256" } | Select-Object -First 1
if (-not $zipAsset) {
  throw "Release v$version does not contain a kit ZIP."
}
$expectedZipName = "opencode-orchestrator-kit-v$version.zip"
if ($zipAsset.name -ne $expectedZipName) {
  throw "Release asset mismatch. Expected $expectedZipName, got $($zipAsset.name)."
}

$temp = Join-Path $env:TEMP ("opencode-orchestrator-kit-update-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $temp | Out-Null
$zip = Join-Path $temp $zipAsset.name
Write-Host "Indiriliyor: v$version" -ForegroundColor Cyan
Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zip -UseBasicParsing -TimeoutSec 180

if (-not $shaAsset) {
  Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
  throw "Release v$version does not contain a .sha256 checksum."
}
$shaResponse = Invoke-WebRequest -Uri $shaAsset.browser_download_url -UseBasicParsing -TimeoutSec 30
$shaText = if ($shaResponse.Content -is [byte[]]) {
  [Text.Encoding]::UTF8.GetString($shaResponse.Content)
} else {
  [string]$shaResponse.Content
}
$expected = ($shaText.Trim() -split '\s+')[0].ToLower()
if ($expected -notmatch '^[a-f0-9]{64}$') {
  Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
  throw "Release v$version has an invalid SHA256 file."
}
$actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $expected) {
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
$kitVersionFile = Join-Path $extract "VERSION"
if (-not (Test-Path $kitVersionFile)) {
  throw "VERSION not found in the downloaded ZIP."
}
$kitVersion = (Get-Content $kitVersionFile -Raw).Trim()
if ($kitVersion -ne $version) {
  throw "Downloaded ZIP VERSION is $kitVersion but the release is v$version."
}
$panelVersionFile = Join-Path $extract "agent-board\VERSION"
if (Test-Path $panelVersionFile) {
  $panelVersion = (Get-Content $panelVersionFile -Raw).Trim()
  if ($panelVersion -ne $version) {
    throw "Downloaded panel VERSION is $panelVersion but the release is v$version."
  }
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
