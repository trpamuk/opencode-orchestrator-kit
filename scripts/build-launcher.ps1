param(
  [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
  throw "csc.exe bulunamadi. .NET Framework 4.x gerekli."
}

if (-not $OutputDir) {
  $OutputDir = Join-Path $root "dist\launcher"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$exe = Join-Path $OutputDir "OpenCodeOrchestratorKit.exe"

& $csc /nologo /target:winexe /platform:anycpu /optimize+ /out:$exe /r:System.Windows.Forms.dll /r:System.Drawing.dll (Join-Path $root "launcher\Program.cs")
if ($LASTEXITCODE -ne 0) {
  throw "Launcher derlenemedi (exit $LASTEXITCODE)."
}

Write-Host "Launcher: $exe" -ForegroundColor Green
