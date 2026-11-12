# OpenCode Orchestrator Kit

**Sürüm:** 0.1.0

OpenCode + OMO-slim + Ajan Panosu + board guard icin tek tik kurulum kiti.

## Gereksinimler

- Windows 10/11
- **OpenCode Desktop 2.x** kurulu
- **Node.js 22+** (panel sunucusu icin)
- **OpenCode Go** erisimi veya uyumlu model erisimi
- Git (board guard'in repo kokunu bulmasi icin onerilir)

## Kurulum

1. Bu klasoru arkadasina ZIP olarak gonder.
2. ZIP'i bir klasore cikar.
3. **`install.cmd`** dosyasina cift tikla.
4. Kurulum bitince **OpenCode Desktop'i tamamen kapatip yeniden ac**.
5. OpenCode Go hesabina gir (yoksa `opencode auth login`).

Kurulum su dosyalari yazar:

```text
%USERPROFILE%\.config\opencode\
  opencode.json
  oh-my-opencode-slim.json
  AGENTS.md
  plugins\board-guard.js
  oh-my-opencode-slim\orchestrator_append.md
  agent-board\
```

Mevcut dosyalar zaman damgali olarak `backups\...-orchestrator-kit` altina yedeklenir.

## Panel

- Yerel adres: **http://127.0.0.1:43124/**
- Masaustu kisayolu: **Ajan Panosu**
- Windows Startup: **Ajan Panosu.lnk** (sunucu otomatik baslar)
- OpenCode icinde: Review pane -> yeni browser sekmesi -> yukaridaki URL

Panel; aktif ajanlari, proje/session bilgisini, board'lari, token/maliyet ve sureleri gosterir.

## Board guard

`plugins\board-guard.js` OpenCode V2 plugin'idir:

- sadece projenin `.opencode/plans/current.md` ve `.opencode/plans/boards/*.md` alanina yazim,
- baska proje/worktree board'larina yazimi reddetme,
- alt ajanlarin board yazmasini reddetme,
- `orchestrator` ve `build` rollerine izin verme.

Plugin OpenCode yeniden baslatildiginda yuklenir. Log: `agent-board\guard.log`.

## Kontrol

```text
doctor.cmd
```

Kontrol ettigi seyler: Node, OpenCode CLI, config dosyalari, OMO-slim 3.0.7, panel health, Startup/masaustu kisayollari, board guard.

## Sorun giderme

### Panel acilmiyor

```powershell
Get-NetTCPConnection -LocalPort 43124 -State Listen
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:43124/health
```

Sunucuyu elle baslat:

```text
%USERPROFILE%\.config\opencode\agent-board\start.vbs
```

### Browser sekmesi OpenCode'da yok

OpenCode Desktop'i **tamamen kapatip yeniden ac**. 2.2.7'de bilinen bir browser pane bug'i var; restart genelde duzeltir. Alternatif olarak paneli normal tarayicida ac.

### Model bulunamadi

OpenCode Go hesabina gir veya `opencode.json` icindeki `model` / OMO config icindeki model ID'lerini kendi erisimine gore degistir.

### Board guard calismiyor

OpenCode'u yeniden baslat. `agent-board\guard.log` dosyasinda `LOAD` satiri gorunmeli.

## Kaldirma

```text
uninstall.cmd
```

Startup/masaustu kisayollarini kaldirir ve panel sunucusunu durdurur. Config dosyalari ve `agent-board` klasoru korunur.

## Notlar

- Bu kit **API key icermez**. Provider girisini kullanici kendi yapar.
- Panel yalnizca `127.0.0.1` uzerinde dinler.
- OMO-slim `3.0.7` olarak pinlenmistir; `autoUpdate` kapalidir.
- Companion kapali gelir.
