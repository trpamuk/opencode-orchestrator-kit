# Kod imzalama (Türkçe)

Kit, `OpenCodeOrchestratorKit.exe` adlı küçük bir .NET Framework launcher taşır. Launcher **varsayılan olarak imzasızdır**. Windows SmartScreen ve public Winget deposu güvenilir bir kod imzası bekler. Public dağıtımdan önce launcher'ı imzala.

İmzalama için yalnızca yayıncının edinebileceği bir **code-signing sertifikası** gerekir. Self-signed sertifika hattı test etmek için kullanılabilir, ancak başka makinelerde güvenilir sayılmaz.

## Gerekenler

- Code-signing sertifikası (OV veya EV), `.pfx` olarak veya `Cert:\CurrentUser\My` içinde.
- PFX şifresi.
- Zaman damgası sunucusu. Varsayılan: `http://timestamp.digicert.com`.

PFX dosyasını, şifresini veya base64 kopyasını repoya **koyma**. GitHub Actions secret'ı veya yerel bir parola yöneticisi kullan.

## Thumbprint ile yerel imzalama

PFX'i bir kez içe aktar:

```powershell
$password = Read-Host -AsSecureString "PFX password"
Import-PfxCertificate -FilePath .\codesign.pfx -CertStoreLocation Cert:\CurrentUser\My -Password $password
Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Format-Table Subject, Thumbprint, NotAfter
```

Release oluştur ve imzala:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\release.ps1 `
  -Version 0.4.18 `
  -CertificateThumbprint <thumbprint> `
  -Publish
```

`release.ps1` launcher'ı derler, imzalar, imzalayan thumbprint'ini doğrular, imzalı EXE'yi ZIP'e koyar ve SHA256/manifestleri günceller.

## PFX yolu ile yerel imzalama

Sertifika deposuna dokunmadan:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\release.ps1 `
  -Version 0.4.18 `
  -PfxPath .\codesign.pfx `
  -PfxPassword "<password>" `
  -Publish
```

`sign.ps1` PFX'i geçici olarak `Cert:\CurrentUser\My` içine alır, imzalar, imzalayanı doğrular ve sertifikayı temizler. `-KeepCertificate` ile sertifikayı bırakabilirsin.

## İmzayı doğrula

```powershell
Get-AuthenticodeSignature .\dist\launcher\OpenCodeOrchestratorKit.exe |
  Format-List Status, StatusMessage, SignerCertificate
```

Güvenilir ve zaman damgalı bir release `Status: Valid` döner. Alternatif:

```powershell
signtool verify /pa /v .\dist\launcher\OpenCodeOrchestratorKit.exe
```

## Self-signed test

Sadece hattı test etmek için. Başka makinelerde güvenilir yapmaz.

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

`-TimestampServer none` çevrimdışı test için zaman damgasını atlar. `-AllowUntrusted`, self-signed sertifikanın ürettiği `UnknownError` durumunu kabul eder.

## GitHub Actions ile imzalama

`Release` workflow'u (`.github/workflows/release.yml`) imzalı release derleyebilir ve yayınlayabilir. `v*` tag push'unda otomatik çalışır; release zaten varsa atlar, yoksa imza secret'larını ister.

1. Sertifikayı PFX olarak dışa aktar.
2. PFX'i base64'e çevir:

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes(".\codesign.pfx")) | Set-Clipboard
   ```

3. Repository secret'ları ekle:
   - `WINDOWS_CERT_PFX_BASE64`: base64 PFX.
   - `WINDOWS_CERT_PASSWORD`: PFX şifresi.
4. Tag ile yayınla:

   ```powershell
   git tag v0.4.13
   git push origin v0.4.13
   ```

   veya **Actions → Release → Run workflow** ile `version` ve `publish` seç.

Secret'lar yoksa tag tetiklemeli yayın bilerek durur; manuel dispatch imzasız build'e izin verir.

## Winget gönderimi

İmzalı ZIP yayınlandıktan sonra:

1. Release ZIP'ini indir ve SHA256'sını doğrula.
2. İçindeki launcher'ın imzalı olduğunu kontrol et:

   ```powershell
   Get-AuthenticodeSignature .\OpenCodeOrchestratorKit.exe
   ```

3. `scripts/release.ps1` ile `dist/packaging/trpamuk.OpenCodeOrchestratorKit.yaml` dosyasını yeniden üret.
4. Manifesti doğrula:

   ```powershell
   winget validate --manifest .\dist\packaging\trpamuk.OpenCodeOrchestratorKit.yaml
   ```

5. `wingetcreate submit` veya pull request ile `microsoft/winget-pkgs` deposuna gönder.

`winget validate` geçse bile public Winget deposu imzasız installer'ı reddedebilir. İmza, tam public Winget listelemesi için kalan tek engeldir.

## Sorun giderme

| Belirti | Çözüm |
|---|---|
| `Certificate not found in Cert:\CurrentUser\My` | PFX'i içe aktar veya `-PfxPath` kullan. |
| `Signing status is UnknownError` | Sertifika zinciri güvenilir değil. Kök/ara sertifikayı yükle veya sadece test için `-AllowUntrusted` kullan. |
| `Signing status is NotTrusted` | Sertifika bu makinede güvenilir değil. Zinciri kontrol et. |
| Zaman damgası isteği başarısız | Ağ/proxy'yi kontrol et veya çevrimdışı test için `-TimestampServer none` kullan. |
| `VERSION is X but -Version is Y` | Release öncesi `VERSION` dosyasını güncelle ve commit'le. |

İngilizce ayrıntılı sürüm: [signing.md](signing.md).
