param(
  [Parameter(Mandatory = $true)][string]$Thumbprint,
  [Parameter(Mandatory = $true)][string]$File,
  [string]$TimestampServer = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $File)) {
  throw "File not found: $File"
}
$cert = Get-ChildItem Cert:\CurrentUser\My |
  Where-Object { $_.Thumbprint -eq $Thumbprint } |
  Select-Object -First 1
if (-not $cert) {
  throw "Code-signing certificate not found in Cert:\CurrentUser\My: $Thumbprint"
}

$result = Set-AuthenticodeSignature -FilePath $File -Certificate $cert -TimestampServer $TimestampServer
if ($result.Status -ne "Valid") {
  throw "Signing failed: $($result.Status) $($result.StatusMessage)"
}
Write-Host "Signed: $File" -ForegroundColor Green
