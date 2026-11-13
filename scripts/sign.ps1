param(
  [string]$Thumbprint = "",
  [string]$PfxPath = "",
  [string]$PfxPassword = "",
  [Parameter(Mandatory = $true)][string]$File,
  [string]$TimestampServer = "http://timestamp.digicert.com",
  [switch]$AllowUntrusted,
  [switch]$KeepCertificate
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $File)) {
  throw "File not found: $File"
}
if (-not $Thumbprint -and -not $PfxPath) {
  throw "Provide either -Thumbprint or -PfxPath."
}

$imported = $null
$cert = $null
try {
  if ($PfxPath) {
    if (-not (Test-Path $PfxPath)) {
      throw "PFX file not found: $PfxPath"
    }
    $secure = ConvertTo-SecureString $PfxPassword -AsPlainText -Force
    $imported = Import-PfxCertificate -FilePath $PfxPath -CertStoreLocation Cert:\CurrentUser\My -Password $secure
    $cert = $imported
  } else {
    $cert = Get-ChildItem Cert:\CurrentUser\My |
      Where-Object { $_.Thumbprint -eq $Thumbprint } |
      Select-Object -First 1
    if (-not $cert) {
      throw "Code-signing certificate not found in Cert:\CurrentUser\My: $Thumbprint"
    }
  }

  $signParams = @{
    FilePath = $File
    Certificate = $cert
  }
  if ($TimestampServer -and $TimestampServer -notin @("none", "skip")) {
    $signParams.TimestampServer = $TimestampServer
  }
  Set-AuthenticodeSignature @signParams | Out-Null

  $signature = Get-AuthenticodeSignature -FilePath $File
  if (-not $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $cert.Thumbprint) {
    throw "Signature was not applied with the requested certificate."
  }
  if ($signature.Status -ne "Valid" -and -not $AllowUntrusted) {
    throw "Signing status is $($signature.Status): $($signature.StatusMessage). Use -AllowUntrusted only for self-signed test certificates."
  }
  Write-Host "Signed: $File" -ForegroundColor Green
  Write-Host "Status: $($signature.Status)" -ForegroundColor DarkGray
  Write-Host "Thumbprint: $($cert.Thumbprint)" -ForegroundColor DarkGray
} finally {
  if ($imported -and -not $KeepCertificate) {
    Remove-Item -Path ("Cert:\CurrentUser\My\" + $imported.Thumbprint) -Force -ErrorAction SilentlyContinue
  }
}
