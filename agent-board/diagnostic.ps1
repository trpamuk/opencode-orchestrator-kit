param(
  [string]$OutputDir = "",
  [string]$PanelUrl = "http://127.0.0.1:43124"
)

$ErrorActionPreference = "Continue"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$tempDir = Join-Path $env:TEMP ("ajan-panosu-diagnostic-" + $stamp)
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

$panel = $PanelUrl
$diagnosticPath = Join-Path $tempDir "diagnostic.json"
try {
  $diagnostic = Invoke-RestMethod -Uri ($panel + "/api/diagnostic") -TimeoutSec 30
  $diagnostic | ConvertTo-Json -Depth 20 | Set-Content -Path $diagnosticPath -Encoding UTF8
} catch {
  @{
    generatedAt = (Get-Date).ToString("o")
    error = $_.Exception.Message
    note = "Panel calismiyor olabilir. Panel health ve doctor.cmd kontrol edin."
  } | ConvertTo-Json -Depth 5 | Set-Content -Path $diagnosticPath -Encoding UTF8
}

$versionFile = Join-Path $PSScriptRoot "VERSION"
if (Test-Path $versionFile) {
  Copy-Item $versionFile (Join-Path $tempDir "VERSION") -Force
}

@"
Ajan Panosu diagnostic bundle
Generated: $stamp
Panel: $panel
"@ | Set-Content -Path (Join-Path $tempDir "README.txt") -Encoding UTF8

$targetDir = if ($OutputDir) { $OutputDir } else { [Environment]::GetFolderPath("Desktop") }
if (-not $targetDir -or -not (Test-Path $targetDir)) { $targetDir = $env:TEMP }
$zip = Join-Path $targetDir ("ajan-panosu-diagnostic-" + $stamp + ".zip")
Compress-Archive -Path (Join-Path $tempDir "*") -DestinationPath $zip -Force
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Diagnostic bundle hazir:" -ForegroundColor Green
Write-Host $zip
