param(
  [string]$Version = "",
  [string]$ZipPath = "",
  [string]$AssetDir = "",
  [switch]$Online,
  [switch]$RequireSignature,
  [string]$Repo = "trpamuk/opencode-orchestrator-kit"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Write-Check([string]$Name, [bool]$Ok, [string]$Detail = "") {
  if ($Ok) {
    Write-Host "[OK]   $Name" -ForegroundColor Green
  } else {
    Write-Host "[FAIL] $Name $Detail" -ForegroundColor Red
  }
  if (-not $Ok) {
    throw "Release verification failed: $Name"
  }
}

function Read-ZipText($Archive, [string]$Name) {
  $entry = $Archive.GetEntry($Name)
  if (-not $entry) {
    throw "ZIP entry missing: $Name"
  }
  $reader = New-Object System.IO.StreamReader($entry.Open())
  try {
    return $reader.ReadToEnd()
  } finally {
    $reader.Dispose()
  }
}

$releaseVersion = $Version.Trim()
if ($releaseVersion.StartsWith("v")) {
  $releaseVersion = $releaseVersion.Substring(1)
}
if (-not $releaseVersion) {
  $releaseVersion = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
}
$zipName = "opencode-orchestrator-kit-v$releaseVersion.zip"
$expectedUrl = "https://github.com/$Repo/releases/download/v$releaseVersion/$zipName"

$temp = $null
if ($Online) {
  $temp = Join-Path $env:TEMP ("opencode-orchestrator-kit-verify-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $temp | Out-Null
  $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/v$releaseVersion" -Headers @{ "User-Agent" = "opencode-orchestrator-kit-verify" } -TimeoutSec 30
  foreach ($asset in $release.assets) {
    $target = Join-Path $temp $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $target -UseBasicParsing -TimeoutSec 180
    Write-Host "Downloaded: $($asset.name)" -ForegroundColor DarkGray
  }
  $ZipPath = Join-Path $temp $zipName
  $AssetDir = $temp
}

if (-not $ZipPath) {
  $ZipPath = Join-Path $root ("dist\" + $zipName)
}
if (-not (Test-Path $ZipPath)) {
  throw "ZIP not found: $ZipPath"
}
if (-not $AssetDir) {
  $AssetDir = Join-Path $root "dist\packaging"
}

$hash = (Get-FileHash $ZipPath -Algorithm SHA256).Hash.ToLower()
Write-Check "ZIP exists" $true
Write-Host "       $ZipPath" -ForegroundColor DarkGray
Write-Host "       SHA256: $hash" -ForegroundColor DarkGray

$shaPath = $ZipPath + ".sha256"
Write-Check "SHA256 file exists" (Test-Path $shaPath) $shaPath
$shaText = (Get-Content $shaPath -Raw).Trim()
$expectedHash = ($shaText -split '\s+')[0].ToLower()
Write-Check "SHA256 matches" ($expectedHash -eq $hash) "expected $expectedHash"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
try {
  $zipVersion = (Read-ZipText $archive "VERSION").Trim()
  Write-Check "ZIP VERSION" ($zipVersion -eq $releaseVersion) "got $zipVersion"

  $panelVersion = (Read-ZipText $archive "agent-board/VERSION").Trim()
  Write-Check "Panel VERSION" ($panelVersion -eq $releaseVersion) "got $panelVersion"

  $required = @(
    "install.ps1",
    "install-gui.ps1",
    "update.ps1",
    "install.sh",
    "doctor.sh",
    "uninstall.sh",
    "OpenCodeOrchestratorKit.exe",
    "launcher/icon.ico",
    "agent-board/server.mjs",
    "agent-board/index.html",
    "scripts/sign.ps1",
    "scripts/release.ps1",
    "scripts/build-icon.ps1",
    "scripts/verify-release.ps1",
    "scripts/test-panel.mjs",
    "scripts/test-board-guard.mjs",
    "docs/signing.md",
    ".github/workflows/release.yml",
    "packaging/scoop/opencode-orchestrator-kit.json",
    "packaging/winget/trpamuk.OpenCodeOrchestratorKit.yaml"
  )
  foreach ($name in $required) {
    Write-Check "ZIP contains $name" ($null -ne $archive.GetEntry($name))
  }

  $launcherTemp = Join-Path $env:TEMP ("opencode-orchestrator-kit-launcher-" + [guid]::NewGuid().ToString("N") + ".exe")
  $entry = $archive.GetEntry("OpenCodeOrchestratorKit.exe")
  $inputStream = $entry.Open()
  $outputStream = [System.IO.File]::Create($launcherTemp)
  try {
    $inputStream.CopyTo($outputStream)
  } finally {
    $outputStream.Dispose()
    $inputStream.Dispose()
  }
  try {
    $fileVersion = (Get-Item $launcherTemp).VersionInfo.FileVersion
    Write-Check "Launcher file version" ($fileVersion -eq $releaseVersion) "got $fileVersion"
    $signature = Get-AuthenticodeSignature $launcherTemp
    Write-Host "       Launcher signature: $($signature.Status)" -ForegroundColor DarkGray
    if ($RequireSignature) {
      Write-Check "Launcher signature is trusted" ($signature.Status -eq "Valid") "got $($signature.Status)"
    }
  } finally {
    Remove-Item $launcherTemp -Force -ErrorAction SilentlyContinue
  }
} finally {
  $archive.Dispose()
}

$scoopPath = Join-Path $AssetDir "opencode-orchestrator-kit.json"
Write-Check "Scoop manifest exists" (Test-Path $scoopPath) $scoopPath
$scoop = Get-Content $scoopPath -Raw | ConvertFrom-Json
Write-Check "Scoop version" ([string]$scoop.version -eq $releaseVersion) "got $($scoop.version)"
Write-Check "Scoop URL" ([string]$scoop.url -eq $expectedUrl) "got $($scoop.url)"
Write-Check "Scoop SHA256" ([string]$scoop.hash -eq $hash) "got $($scoop.hash)"

$wingetPath = Join-Path $AssetDir "trpamuk.OpenCodeOrchestratorKit.yaml"
Write-Check "Winget manifest exists" (Test-Path $wingetPath) $wingetPath
$winget = Get-Content $wingetPath -Raw
$wingetVersion = [regex]::Match($winget, "(?m)^PackageVersion:\s*(\S+)").Groups[1].Value
$wingetUrl = [regex]::Match($winget, "(?m)^\s*InstallerUrl:\s*(\S+)").Groups[1].Value
$wingetHash = [regex]::Match($winget, "(?m)^\s*InstallerSha256:\s*(\S+)").Groups[1].Value
Write-Check "Winget version" ($wingetVersion -eq $releaseVersion) "got $wingetVersion"
Write-Check "Winget URL" ($wingetUrl -eq $expectedUrl) "got $wingetUrl"
Write-Check "Winget SHA256" ($wingetHash -eq $hash) "got $wingetHash"

if ($temp) {
  Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ""
Write-Host "Release v$releaseVersion verified." -ForegroundColor Green
