param(
  [string]$OutputDir = "",
  [string]$Version = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
  throw "csc.exe bulunamadi. .NET Framework 4.x gerekli."
}

if (-not $Version) {
  $Version = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
}
if (-not $OutputDir) {
  $OutputDir = Join-Path $root "dist\launcher"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$exe = Join-Path $OutputDir "OpenCodeOrchestratorKit.exe"
$assemblyInfo = Join-Path $OutputDir "AssemblyInfo.g.cs"
$icon = Join-Path $root "launcher\icon.ico"
if (-not (Test-Path $icon)) {
  throw "launcher\icon.ico bulunamadi. Once scripts\build-icon.ps1 calistir."
}

@"
[assembly: System.Reflection.AssemblyVersion("$Version")]
[assembly: System.Reflection.AssemblyFileVersion("$Version")]
"@ | Set-Content -Path $assemblyInfo -Encoding utf8

$cscArgs = @(
  "/nologo",
  "/target:winexe",
  "/platform:anycpu",
  "/optimize+",
  "/out:$exe",
  "/r:System.Windows.Forms.dll",
  "/r:System.Drawing.dll",
  "/win32icon:$icon",
  (Join-Path $root "launcher\Program.cs"),
  $assemblyInfo
)
& $csc @cscArgs
if ($LASTEXITCODE -ne 0) {
  throw "Launcher derlenemedi (exit $LASTEXITCODE)."
}

Write-Host "Launcher: $exe (v$Version)" -ForegroundColor Green
