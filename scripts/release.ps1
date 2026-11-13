param(
  [string]$Version = "",
  [switch]$Publish,
  [string]$Notes = "",
  [string]$CertificateThumbprint = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Write-NoBom([string]$path, [string]$text) {
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [IO.File]::WriteAllText($path, $text, $utf8)
}

if (-not $Version) {
  $Version = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
}

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$launcherDir = Join-Path $dist "launcher"
& (Join-Path $PSScriptRoot "build-launcher.ps1") -OutputDir $launcherDir
$launcher = Join-Path $launcherDir "OpenCodeOrchestratorKit.exe"
if ($CertificateThumbprint) {
  & (Join-Path $PSScriptRoot "sign.ps1") -Thumbprint $CertificateThumbprint -File $launcher
}

$zip = Join-Path $dist ("opencode-orchestrator-kit-v" + $Version + ".zip")
if (Test-Path $zip) { Remove-Item $zip -Force }
git archive --format=zip --output=$zip HEAD

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Update)
try {
  $entry = $archive.GetEntry("OpenCodeOrchestratorKit.exe")
  if ($entry) { $entry.Delete() }
  [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $launcher, "OpenCodeOrchestratorKit.exe") | Out-Null
} finally {
  $archive.Dispose()
}

$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
$shaFile = $zip + ".sha256"
Write-NoBom $shaFile ($hash + "  " + (Split-Path $zip -Leaf) + "`n")

$pkg = Join-Path $dist "packaging"
New-Item -ItemType Directory -Force -Path $pkg | Out-Null
$url = "https://github.com/trpamuk/opencode-orchestrator-kit/releases/download/v" + $Version + "/" + (Split-Path $zip -Leaf)

$scoopTemplate = Get-Content (Join-Path $root "packaging\scoop\opencode-orchestrator-kit.json") -Raw
$scoop = $scoopTemplate.Replace("__VERSION__", $Version).Replace("__URL__", $url).Replace("__SHA256__", $hash)
Write-NoBom (Join-Path $pkg "opencode-orchestrator-kit.json") $scoop

$wingetTemplate = Get-Content (Join-Path $root "packaging\winget\trpamuk.OpenCodeOrchestratorKit.yaml") -Raw
$winget = $wingetTemplate.Replace("__VERSION__", $Version).Replace("__URL__", $url).Replace("__SHA256__", $hash)
$wingetPath = Join-Path $pkg "trpamuk.OpenCodeOrchestratorKit.yaml"
Write-NoBom $wingetPath $winget

if (Get-Command winget -ErrorAction SilentlyContinue) {
  winget validate --manifest $wingetPath
  if ($LASTEXITCODE -ne 0) {
    throw "Winget manifest validation failed."
  }
}

Write-Host "ZIP: $zip"
Write-Host "SHA256: $hash"
Write-Host "Scoop manifest: $(Join-Path $pkg 'opencode-orchestrator-kit.json')"
Write-Host "Winget manifest: $(Join-Path $pkg 'trpamuk.OpenCodeOrchestratorKit.yaml')"

if ($Publish) {
  $status = git status --porcelain
  if ($status) {
    throw "Working tree dirty. Commit before publishing."
  }
  if (-not $Notes) {
    $Notes = "Release v" + $Version
  }
  gh release create ("v" + $Version) $zip $shaFile (Join-Path $pkg "opencode-orchestrator-kit.json") (Join-Path $pkg "trpamuk.OpenCodeOrchestratorKit.yaml") --title ("v" + $Version) --notes $Notes
}
