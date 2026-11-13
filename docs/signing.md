# Code signing

The kit ships `OpenCodeOrchestratorKit.exe`, a small .NET Framework launcher for the WinForms installer. The launcher is **unsigned by default**. Windows SmartScreen and the public Winget repository expect a trusted code signature, so sign the launcher before a public release.

Signing requires a **code-signing certificate** that only the publisher can obtain. A self-signed certificate is useful for testing the pipeline, but it is not trusted by other machines.

## What you need

- A code-signing certificate (OV or EV) exported as a `.pfx` file, or imported into `Cert:\CurrentUser\My`.
- The PFX password.
- A timestamp server URL. The default is `http://timestamp.digicert.com`.

Never commit a PFX file, its password, or a base64 copy of it. Use GitHub Actions secrets or a local password manager.

## Local signing with a thumbprint

Import the PFX once:

```powershell
$password = Read-Host -AsSecureString "PFX password"
Import-PfxCertificate -FilePath .\codesign.pfx -CertStoreLocation Cert:\CurrentUser\My -Password $password
Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Format-Table Subject, Thumbprint, NotAfter
```

Build and sign a release:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\release.ps1 `
  -Version 0.4.5 `
  -CertificateThumbprint <thumbprint> `
  -Publish
```

`release.ps1` builds the launcher, signs it, verifies the signer thumbprint, injects the signed EXE into the ZIP, and updates the SHA256 and manifests.

## Local signing with a PFX path

You can skip the certificate store:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\release.ps1 `
  -Version 0.4.5 `
  -PfxPath .\codesign.pfx `
  -PfxPassword "<password>" `
  -Publish
```

`sign.ps1` imports the PFX temporarily into `Cert:\CurrentUser\My`, signs the file, verifies the signer, and removes the imported certificate. Use `-KeepCertificate` to keep it.

## Verify a signature

```powershell
Get-AuthenticodeSignature .\dist\launcher\OpenCodeOrchestratorKit.exe |
  Format-List Status, StatusMessage, SignerCertificate
```

A trusted, timestamped release reports `Status: Valid`. You can also run:

```powershell
signtool verify /pa /v .\dist\launcher\OpenCodeOrchestratorKit.exe
```

## Self-signed test

Use this only to test the pipeline. It does not make the installer trusted on other machines.

```powershell
$cert = New-SelfSignedCertificate `
  -Type CodeSigningCert `
  -Subject "CN=OpenCode Orchestrator Kit Test" `
  -KeyExportPolicy Exportable `
  -KeyUsage DigitalSignature `
  -CertStoreLocation Cert:\CurrentUser\My `
  -NotAfter (Get-Date).AddDays(1)

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\sign.ps1 `
  -Thumbprint $cert.Thumbprint `
  -File .\dist\launcher\OpenCodeOrchestratorKit.exe `
  -TimestampServer none `
  -AllowUntrusted

Get-AuthenticodeSignature .\dist\launcher\OpenCodeOrchestratorKit.exe

Get-ChildItem Cert:\CurrentUser\My |
  Where-Object { $_.Subject -eq "CN=OpenCode Orchestrator Kit Test" } |
  Remove-Item -Force
```

`-TimestampServer none` skips timestamping for offline tests. `-AllowUntrusted` accepts the `UnknownError` status that a self-signed certificate produces.

## Signing in GitHub Actions

The `Release` workflow (`.github/workflows/release.yml`) can build and optionally publish a signed release.

1. Export the code-signing certificate as a PFX.
2. Base64-encode the PFX:

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes(".\codesign.pfx")) | Set-Clipboard
   ```

3. Add repository secrets:
   - `WINDOWS_CERT_PFX_BASE64`: the base64 PFX.
   - `WINDOWS_CERT_PASSWORD`: the PFX password.
4. Run **Actions → Release → Run workflow**:
   - `version`: must match `VERSION` in the repository.
   - `publish`: enable to create the GitHub release and upload assets.

If the secrets are missing, the workflow builds an unsigned release and prints a warning.

## Winget submission

After the signed ZIP is published:

1. Download the release ZIP and verify its SHA256.
2. Confirm the embedded launcher is signed:

   ```powershell
   Get-AuthenticodeSignature .\OpenCodeOrchestratorKit.exe
   ```

3. Regenerate `dist/packaging/trpamuk.OpenCodeOrchestratorKit.yaml` with `scripts/release.ps1`.
4. Validate it:

   ```powershell
   winget validate --manifest .\dist\packaging\trpamuk.OpenCodeOrchestratorKit.yaml
   ```

5. Submit the manifest to `microsoft/winget-pkgs` with `wingetcreate submit` or a pull request.

The public Winget repository may still reject an unsigned installer even when `winget validate` passes. Signing is the remaining blocker for a fully public Winget listing.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Certificate not found in Cert:\CurrentUser\My` | Import the PFX or pass `-PfxPath`. |
| `Signing status is UnknownError` | The certificate chain is not trusted. Install the root/intermediate certificate or use `-AllowUntrusted` for tests only. |
| `Signing status is NotTrusted` | The certificate is not trusted on this machine. Check the certificate chain. |
| Timestamp request fails | Check the network/proxy, or pass `-TimestampServer none` for an offline test build. |
| `VERSION is X but -Version is Y` | Bump and commit `VERSION` before building the release. |
