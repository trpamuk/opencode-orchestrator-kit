# OpenCode Orchestrator Kit

**Version:** 0.4.13  
**Platform:** Windows 10/11, macOS/Linux (experimental)  
**Status:** early public preview

A one-click Windows bootstrap for a practical multi-agent OpenCode setup:

- [OpenCode Desktop](https://opencode.ai/desktop) as the runtime
- [OMO-slim](https://github.com/alvinunreal/oh-my-opencode-slim) as the orchestrator
- **Ajan Panosu** as a project-aware live dashboard
- **Board Guard** as a write-isolation plugin for task boards

> This is an independent community project. It is not affiliated with or endorsed by OpenCode or OMO-slim.

---

## Recent highlights

- **Update awareness:** the dashboard shows its version and checks the latest GitHub release.
- **Safer writes:** every panel write endpoint requires a per-process token, not just a same-origin request.
- **Model health test:** test a model with a tiny temporary session before assigning it to an agent.
- **Primary + fallback models:** each agent can have a fallback chain.
- **Preset switching:** switch between `session` and `opencode-go` from the dashboard.
- **Per-project profiles:** a project can override agent models without changing the global setup.
- **Automation controls:** configurable stuck threshold, opt-in auto-stop and Web Notifications.
- **Deeper session detail:** live refresh, tool filter, copy error, lineage tree and retry.
- **Operations:** agent analytics, Board Guard log viewer, board archive button and diagnostic bundle.
- **Installers:** WinForms GUI on Windows and an experimental `install.sh` for macOS/Linux.
- **Release tooling:** SHA256 checksums, Scoop manifest, Winget template and GitHub Actions CI.
- **Signing pipeline:** PFX/thumbprint signing, a CI signing smoke test and an optional signed release workflow.
- **Branded launcher:** a generated multi-size icon is embedded in `OpenCodeOrchestratorKit.exe`.
- **Tag releases:** pushing a `v*` tag triggers the Release workflow; existing releases are skipped safely.

---

## Why this exists

OMO-slim is a strong orchestration layer, but it does not provide a first-class, project-aware dashboard inside OpenCode Desktop. Its Companion is a floating status overlay, and it can be unreliable when several projects or sessions are active.

This kit adds the missing operational layer:

- a live view of active agents, sessions, projects, models, duration, tokens and cost;
- strict project and board isolation;
- a board guard that prevents subagents from writing to the wrong task board;
- board lifecycle support for active and archived work;
- a simple Windows installer so another user can reproduce the setup.

It does **not** replace OpenCode or OMO-slim. It configures them and adds the missing visibility and board-safety layer.

---

## What you get

| Component | Purpose |
|---|---|
| `opencode.json` bootstrap | Enables OMO-slim 3.0.7 and selects the orchestrator |
| OMO-slim config | Session-model preset, optional OpenCode Go preset, marketplace agents, Companion disabled, 30-minute background-task timeout |
| Global `AGENTS.md` | Board, worktree, review and merge policy |
| `orchestrator_append.md` | Mandatory automatic orchestration workflow |
| `plugins/board-guard.js` | OpenCode V2 plugin that isolates board writes |
| `agent-board/` | Ajan Panosu local dashboard and avatars |
| Startup shortcut | Starts the dashboard server automatically |
| Desktop shortcut | Opens the dashboard in a browser |
| `OpenCodeOrchestratorKit.exe` | .NET Framework WinExe launcher for the GUI installer |
| `launcher/icon.ico` | Multi-size launcher icon |
| `scripts/build-icon.ps1` | Regenerates `launcher/icon.ico` |
| `install-gui.cmd` | Optional WinForms installer with model selection |
| `update.cmd` | SHA256-verified one-click update |
| `install.sh` | Experimental macOS/Linux installer |
| `doctor.sh` | macOS/Linux setup checks |
| `uninstall.sh` | macOS/Linux service/shortcut removal; `--purge` removes kit files |
| `diagnostic.cmd` | Creates a redacted diagnostic ZIP |
| `scripts/release.ps1` | Maintainer release, SHA256 and packaging helper |
| `scripts/sign.ps1` | Code-signing helper for a user-provided certificate |
| `scripts/verify-release.ps1` | Verifies local or online release assets, SHA256, versions and signature |
| `scripts/test-panel.mjs` | Panel token, origin, asset-traversal and diagnostic-redaction tests |
| `scripts/test-board-guard.mjs` | Board isolation, worktree and agent-permission tests |
| `.github/workflows/ci.yml` | Windows and Linux CI for syntax, installers, config, signing and isolation tests |
| `.github/workflows/release.yml` | Optional signed release workflow |
| `docs/signing.md` | Code-signing and Winget submission guide |
| `doctor.cmd` | Checks the installed setup |
| `uninstall.cmd` | Removes shortcuts and stops the dashboard server |

---

## Requirements

Before running the kit, install:

1. **OpenCode Desktop 2.3.x** (2.x supported; 2.3.0 is the tested version)
2. **Node.js 22+**
3. **Any working provider/model configured in OpenCode** (OpenCode Go is optional)
4. **Git** (recommended; Board Guard uses it to resolve the repository root)

The kit does **not** install OpenCode Desktop or Node.js. It also does **not** contain provider API keys and does **not** pin a model by default.

---

## Installation order

This is the important part:

```text
1. Install OpenCode Desktop 2.x
2. Configure a provider and select a model in OpenCode (any provider; OpenCode Go is optional)
3. Install Node.js 22+
4. Extract this kit and run install.cmd, install-gui.cmd, or double-click OpenCodeOrchestratorKit.exe
5. Fully quit and reopen OpenCode Desktop
6. Open the dashboard
```

On Windows, `install-gui.cmd` offers a WinForms wizard with a searchable model list. On macOS/Linux, use `bash install.sh` (experimental) and select the model inside OpenCode. Check the setup with `bash doctor.sh`; remove the service and shortcuts with `bash uninstall.sh`, or add `--purge` to remove the installed kit files while keeping your OpenCode config.

You do **not** need to install OMO-slim manually. The kit writes the OMO-slim plugin configuration and lets OpenCode install the pinned `oh-my-opencode-slim@3.0.7` package on startup.

You do **not** need an OpenCode Go subscription. The default preset inherits the model you selected in OpenCode. See [Model freedom](#model-freedom).

If OMO-slim is already installed, the installer backs up the existing global config and replaces the orchestration config with the kit version. Existing `opencode.json` provider settings and your selected model are preserved and merged.

---

## Model freedom

The kit does **not** require OpenCode Go and does **not** pin a model by default.

The default `session` preset:

- leaves `opencode.json` without a `model` field;
- sets `stripOrchestratorModel: true`;
- makes the orchestrator and built-in subagents use the model selected in the current OpenCode session.

So the user can pick any provider/model in OpenCode and the orchestration follows it.

The kit also ships an optional `opencode-go` preset with the tested DeepSeek/OpenCode Go models. To switch:

```text
%USERPROFILE%\.config\opencode\oh-my-opencode-slim.json
```

```json
"preset": "opencode-go"
```

Per-agent overrides are still possible. For example, to give only the oracle a specific model:

```json
"oracle": {
  "model": ["your-provider/your-model"],
  "skills": ["simplify"]
}
```

To make an agent follow the session model explicitly, use:

```json
"oracle": {
  "inheritModelFrom": "session",
  "skills": ["simplify"]
}
```

> **Observer note:** Observer inherits the session model in the `session` preset. If your model is not multimodal, set a vision-capable model for `observer` or disable it with `"disabled_agents": ["observer"]`.

---

## Quick start

1. Download the latest release ZIP.
2. Extract it to a normal folder.
3. Double-click **`install.cmd`**.
4. When prompted, choose a model or keep the current one. The installer lists models from the running OpenCode service.
5. Wait for the installer to finish.
6. Fully quit and reopen OpenCode Desktop.
7. Open **http://127.0.0.1:43124/**.

For the in-app browser:

```text
OpenCode Desktop -> Review pane -> new browser tab -> http://127.0.0.1:43124/
```

If the Browser entry is missing after an OpenCode update, fully quit and reopen Desktop. This is a known OpenCode Desktop issue in some 2.2.x builds.

---

## What the installer does

- Checks Node.js and reports the OpenCode CLI when available.
- Creates a timestamped backup under:

```text
%USERPROFILE%\.config\opencode\backups\<timestamp>-orchestrator-kit
```

- Merges the kit plugin and default agent into an existing `opencode.json`. It does **not** change the model you selected.
- Lists available models from the running OpenCode service and lets you choose one. Use `-NoModelPrompt` to skip the prompt or `-Model "provider/model"` to preselect one.
- Warns when no model is selected, so the first run can be completed from OpenCode or the dashboard.
- Writes the OMO-slim configuration, global `AGENTS.md` and orchestrator policy.
- Installs `plugins\board-guard.js`.
- Copies the dashboard to `%USERPROFILE%\.config\opencode\agent-board`.
- Generates a machine-specific `start.vbs` using the detected Node.js path.
- Creates a Windows Startup shortcut and a desktop URL shortcut.
- Starts the dashboard server and verifies `/health`.

The kit never writes provider API keys.

### Re-running the installer

The installer is safe to re-run. It:

- stops the local dashboard server first,
- copies the dashboard into a staging folder and validates it,
- preserves the existing `guard.log`,
- preserves your `session`/`opencode-go` preset choice and your selected model,
- backs up the current config and dashboard,
- swaps the new files into place,
- restarts the dashboard and checks `/health`.

If the staging copy is incomplete, the installer stops before touching the current dashboard.

### One-click update

Run **`update.cmd`** (or `update.ps1`). It:

- reads the latest GitHub release,
- downloads the kit ZIP and its `.sha256`,
- requires and verifies the SHA256 before extracting,
- runs the same safe installer with your existing config.

Use `-Yes` for unattended mode and `-Force` to reinstall the same version. Use `-Version 0.4.8` to install or roll back to a specific release. The updater preserves your model, preset choice and `guard.log`, requires the release `.sha256`, and verifies that the release tag, asset name and embedded `VERSION` files match before installing.

Use `-CheckOnly` to check the latest or a specific release without downloading:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File update.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File update.ps1 -CheckOnly -Version 0.4.8
```

### Maintainer release and signing

`scripts\release.ps1` builds the launcher, injects it into the ZIP, writes the SHA256, regenerates the Scoop/Winget manifests and optionally publishes with `gh`.

To sign the launcher, pass a certificate thumbprint (or `-PfxPath` / `-PfxPassword`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\release.ps1 `
  -Version 0.4.13 `
  -CertificateThumbprint <thumbprint> `
  -Publish
```

The `Release` GitHub Actions workflow can build and publish with the `WINDOWS_CERT_PFX_BASE64` and `WINDOWS_CERT_PASSWORD` repository secrets. Pushing a `v*` tag triggers it automatically; if a release already exists it skips, otherwise it builds and publishes (signing secrets are required for tag-triggered publishing). See [docs/signing.md](docs/signing.md) for certificate setup, verification, self-signed testing and Winget submission.

Verify a local or published release:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-release.ps1 -Version 0.4.13
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-release.ps1 -Version 0.4.13 -Online -RequireSignature
```

The verifier checks the SHA256, embedded `VERSION` files, required ZIP entries, launcher version and signature, and the Scoop/Winget manifest URLs and hashes.

---

## Dashboard

**Ajan Panosu** is a local, read-only operational dashboard.

It shows:

- active agents across sessions;
- official agent names and roles;
- session title, parent/child relationship, model and project;
- elapsed time, last activity, input/output tokens and cost;
- **Alt Görevler**: running `subagent`/`task` tool calls inside a session, even when they never create a separate child session;
- a red **takıldı?** state when a session or subagent task has not updated for 15 minutes;
- a **Durdur** button on stuck cards; it asks for confirmation and interrupts only that session's current run;
- a **Modeller** button for per-agent model profiles, fallback chains, preset switching, model testing and per-project profiles;
- a **Detay** button with live refresh, tool filter, copy error, lineage tree and retry;
- a **Ayarlar** dialog for stuck threshold, opt-in auto-stop, opt-in auto-retry, Web Notifications and diagnostic download;
- an **Analitik** view with sessions, success/fail counts, average duration, tokens, cost and stuck tasks per agent;
- a **Guard** view for the Board Guard log;
- an **Arşivle** button on active boards;
- a version badge and GitHub update check;
- a first-run banner when OpenCode has no default model selected;
- active task boards, parsed from the project's `.opencode/plans/` area;
- a project selector so two projects never share one board view.

The dashboard keeps child and worktree sessions attached to their parent project, so a worktree subagent cannot disappear from the main project view.

The server binds only to `127.0.0.1:43124`. It reads the local OpenCode service password from `service.json` on the server side and never sends it to the browser.

### Model profiles in the dashboard

Click **Modeller** in the header to edit the active OMO preset per agent:

- choose **Oturum modeli** to inherit the model selected in OpenCode;
- choose a specific model for orchestrator, oracle, explorer, designer, fixer or observer;
- choose an optional **fallback** model for each agent;
- choose a reasoning variant when the model exposes variants;
- click **Test** to run a tiny temporary session and verify the model actually responds;
- switch the active preset between `session` and `opencode-go`;
- enable **Bu proje için** to write a project-level profile to `<project>\.opencode\oh-my-opencode-slim.json` instead of the global config.

Global changes are written to `%USERPROFILE%\.config\opencode\oh-my-opencode-slim.json`, with a timestamped backup under the same folder. Project profiles are backed up under `<project>\.opencode\backups\`. The model list comes from OpenCode and is sanitized: provider API keys and settings are never sent to the browser.

### Session detail

Click **Detay** on any session or subagent card to see:

- agent, model, outcome, tokens, cost and last activity;
- the most recent tool calls with status, duration and a short description;
- tool errors and the session error, with common secret patterns redacted;
- a tool filter, live refresh, copy-error and session-ID buttons;
- a lineage tree of parent/child sessions;
- a **Yeniden dene** button for a stuck subagent, which sends a retry prompt to the parent session.

The detail view is read-only apart from **Durdur** and **Yeniden dene**.

---

## Board Guard

Board Guard is an OpenCode V2 plugin.

It enforces:

- writes only to the project's `.opencode/plans/current.md` or `.opencode/plans/boards/*.md`;
- no writes to another project or worktree board;
- no board writes from subagents or reviewers;
- writes allowed only for `orchestrator` and `build`;
- denied attempts recorded in `agent-board\guard.log`.

Board Guard loads when OpenCode starts. After installing the kit, restart OpenCode once.

---

## Board lifecycle

Task boards are working state, not permanent history.

- Active feature boards live in `.opencode/plans/boards/`.
- `current.md` is an index/legacy board.
- Completed boards are archived under `.opencode/plans/archive/<YYYY-MM>/boards/`.
- Worktrees use the main repository's board; they do not create separate boards.

---

## Troubleshooting

### Dashboard does not open

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:43124/health
```

Start it manually:

```text
%USERPROFILE%\.config\opencode\agent-board\start.vbs
```

### Browser tab is missing in OpenCode Desktop

Some 2.2.x Desktop builds temporarily lost the Browser launcher. The kit is tested with OpenCode Desktop 2.3.0; if the entry is still missing, fully quit and reopen Desktop. You can use the desktop `Ajan Panosu` shortcut in the meantime.

### Model not found / no model selected

Select a provider and a model in OpenCode first. The kit does not pin a model in the default `session` preset.

The dashboard shows a **Model seçili değil** banner when OpenCode has no default model. Click **Modeller** to set per-agent profiles, or select a model in OpenCode. `doctor.cmd` also checks the default model and reports `Varsayilan model` as failed until one is selected.

To use the tested OpenCode Go setup instead, set this in `%USERPROFILE%\.config\opencode\oh-my-opencode-slim.json`:

```json
"preset": "opencode-go"
```

Then sign in to OpenCode Go. For per-agent model overrides, edit the `model` or `inheritModelFrom` fields in the same file.

### Board Guard is not active

Restart OpenCode and check that `agent-board\guard.log` contains a `LOAD` or `SETUP` line.

### A subagent is stuck in the background

OpenCode 2.2.x can leave a native `subagent(..., background: true)` call running indefinitely. The call may never create a visible child session, so the normal session list cannot show it. On this host, OMO-slim also reports:

```text
runtime status reconciliation disabled on this host (client.session.status unavailable)
```

The dashboard now surfaces these calls directly:

- open the project that owns the parent session;
- check the **Alt Görevler** section;
- a task that has not updated for 15 minutes is marked **takıldı?**;
- click **Durdur** on the stuck card and confirm. This calls OpenCode's session interrupt and stops only the current run; it does not delete files or change task boards;
- check `git status` before re-running the task, because a stopped fixer may leave uncommitted changes;
- if the session does not clear, fully restart OpenCode Desktop.

The kit also sets `backgroundJobs.wallClockTimeoutMs` to `1800000` (30 minutes) in the OMO-slim config. This aborts a background child session that was launched successfully. It cannot stop a native tool call that hangs before creating a child session; the dashboard warning is the early-warning path for that case.

If the problem repeats and you prefer reliability over parallel background work, you can force same-provider subagents to run in the foreground:

```json
"backgroundJobs": {
  "sameProviderPolicy": {
    "opencode-go": "foreground"
  }
}
```

This avoids the native background path entirely, at the cost of serializing those subagents.

### Update badge

The dashboard checks the latest GitHub release once an hour. If a newer release exists, click the green badge to open the release page, or run `update.cmd` for a SHA256-verified one-click update. Re-running `install.cmd` is also safe and preserves your model, preset choice and `guard.log`.

The kit is tested with **OpenCode Desktop 2.3.0** and **OMO-slim 3.0.7**. OMO-slim 3.0.7 was the latest release at the time of writing.

### Notifications and auto-stop

Open **Ayarlar** and click **Bildirim izni**. Web Notifications are used for stuck tasks and failed/interrupted sessions. **Otomatik durdur** is opt-in and only triggers after the stuck threshold plus five minutes. It calls the same guarded interrupt endpoint as the **Durdur** button. **Otomatik yeniden dene** is also opt-in; after an auto-stop it sends one retry prompt 30 seconds later, once per stuck session.

### Per-project profile

Enable **Bu proje için** in the **Modeller** dialog to write `<project>\.opencode\oh-my-opencode-slim.json`. Use **Proje profilini sıfırla** to return to the global profile. Project profiles are cloned from the currently active global preset; re-save after changing the global preset.

### Model test fails

The **Test** button creates a temporary session, sends a tiny prompt, waits for a reply and deletes the session. A failure usually means the provider is offline, the model does not support chat/tools, or the selected variant is invalid. Check the model in OpenCode first.

### Diagnostic bundle

```text
%USERPROFILE%\.config\opencode\agent-board\diagnostic.cmd
```

This creates a ZIP on the Desktop containing a redacted `diagnostic.json`, the kit version and a README. The dashboard's **Ayarlar → JSON indir** button downloads the same redacted JSON directly.

### Full diagnostic

```text
doctor.cmd
```

---

## Security and privacy

- No provider API keys are included in this repository or release.
- `service.json`, `.env`, backups, logs and local ZIPs are excluded by `.gitignore`.
- The dashboard listens on loopback only.
- The **Durdur** button uses a local `POST /api/interrupt` endpoint. It accepts only same-origin requests and only active sessions that have a running subagent task. It interrupts execution; it never deletes files or boards.
- Every panel write endpoint (`/api/interrupt`, `/api/profile`, `/api/preset`, `/api/project-profile/reset`, `/api/archive-board`, `/api/model-test`, `/api/retry`) requires a per-process `X-Panel-Token` injected into the panel HTML.
- The model list is sanitized before it reaches the browser; provider API keys and settings are never sent.
- The diagnostic endpoint redacts common secret patterns from config summaries and log tails.
- Project profiles are written only to `<project>\.opencode\oh-my-opencode-slim.json` after validating that the project directory exists.
- `update.cmd` requires the release `.sha256` and verifies it before extracting or running the installer.
- `OpenCodeOrchestratorKit.exe` is unsigned by default. Sign it with `scripts\sign.ps1` and a trusted code-signing certificate before public distribution. See [docs/signing.md](docs/signing.md).
- Do not expose port `43124` to a LAN or the internet without an authenticated reverse proxy.
- Review third-party OpenCode plugins before installing them.

See [SECURITY.md](SECURITY.md).

---

## Uninstall

```text
uninstall.cmd
```

This removes the Startup and desktop shortcuts and stops the dashboard server. Configuration files and the `agent-board` folder are preserved unless you delete them manually.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Türkçe

**Sürüm:** 0.4.13  
**Platform:** Windows 10/11, macOS/Linux (deneysel)

Bu kit, OpenCode Desktop + OMO-slim + Ajan Panosu + Board Guard kurulumunu tek tıkla yapar.

### Neden var?

OMO-slim güçlü bir orkestrasyon katmanıdır; ancak OpenCode Desktop içinde proje bazlı, düzgün bir canlı paneli yoktur. Companion yüzen bir durum penceresidir ve çok sayıda proje/oturum açıkken yeterince güvenilir değildir. Bu kit; aktif ajanları, oturumları, board'ları, token/maliyeti gösteren yerel bir panel ve board yazımını izole eden bir guard ekler.

### Kurulum sırası

1. OpenCode Desktop 2.x kur.
2. OpenCode'da istediğin provider/model'i seç. **OpenCode Go şart değil.**
3. Node.js 22+ kur.
4. ZIP'i çıkar ve `install.cmd`, `install-gui.cmd` veya `OpenCodeOrchestratorKit.exe` çalıştır.
5. OpenCode Desktop'ı tamamen kapatıp yeniden aç.
6. Paneli aç: `http://127.0.0.1:43124/`

macOS/Linux'ta `bash install.sh`, `bash doctor.sh` ve `bash uninstall.sh` kullanılabilir (deneysel). OMO-slim'i ayrıca kurmana gerek yok; kit gerekli config'i yazar ve OpenCode `oh-my-opencode-slim@3.0.7` paketini kendisi yükler.

### Model özgürlüğü

Kit varsayılan olarak **hiçbir model ID'si yazmaz**. `session` preset'i, OpenCode oturumunda seçtiğin modeli orchestrator ve alt ajanlara uygular. `opencode.json` içindeki model ayarına dokunulmaz.

İstersen test edilmiş OpenCode Go preset'ine geçebilirsin:

```json
"preset": "opencode-go"
```

Ayar dosyası: `%USERPROFILE%\.config\opencode\oh-my-opencode-slim.json`

Installer çalışırken OpenCode servisindeki modelleri listeler; mevcut modeli koru, listeden seç veya model alanını boş bırak seçeneklerini sunar. `-NoModelPrompt` ile soru atlanır, `-Model "provider/model"` ile model önceden seçilir.

Panelde **Modeller** butonu agent bazlı override yazar; birincil + yedek model, model testi ve `session`/`opencode-go` preset geçişi sunar. **Bu proje için** seçilirse ayar `<proje>\.opencode\oh-my-opencode-slim.json` dosyasına yazılır. Değişiklikten önce yedek alınır ve provider API key'leri tarayıcıya gönderilmez.

Tek bir ajana özel model vermek için `model`, oturum modelini takip etmesi için `inheritModelFrom: "session"` kullanılabilir. Observer görsel model gerektirir; oturum modelin multimodal değilse observer'a ayrı model ver veya `"disabled_agents": ["observer"]` ile kapat.

### Panel

- Yerel adres: `http://127.0.0.1:43124/`
- Masaüstü kısayolu: `Ajan Panosu`
- OpenCode içinde: Review pane → yeni browser sekmesi → aynı URL
- Sunucu Startup'ta otomatik başlar.
- **Alt Görevler** bölümü, oturum içinde çalışan `subagent`/`task` çağrılarını gösterir; ayarlanabilir eşikten (varsayılan 15 dk) sonra `takıldı?` olur.
- Takılı kartlarda **Durdur** butonu vardır; onay ister ve sadece o oturumun mevcut çalışmasını keser. Dosya/board değiştirmez; tekrar çalıştırmadan önce `git status` kontrol edilmeli.
- **Modeller** butonu ile orchestrator, oracle, explorer, designer, fixer ve observer için oturum modeli, belirli model, yedek model, variant ve model testi kullanılabilir.
- **Detay** butonu son tool çağrılarını, hataları, modeli, token/maliyeti, oturum ağacını gösterir; canlı yenileme, tool filtresi, hata kopyalama ve **Yeniden dene** vardır.
- **Ayarlar** ile takılma eşiği, opt-in otomatik durdurma, opt-in otomatik yeniden deneme (30 sn sonra 1 kez), Web Bildirimleri ve diagnostic indirme ayarlanır.
- **Analitik** agent bazlı başarı/hata/süre/maliyet/stuck tablosu gösterir.
- **Guard** Board Guard log'unu, **Arşivle** aktif board'u arşive taşımayı sağlar.
- Sürüm rozeti ve GitHub güncelleme kontrolü vardır.
- OpenCode'da varsayılan model yoksa panelde uyarı bandı çıkar.

### Board Guard

Sadece projenin `.opencode/plans/current.md` ve `.opencode/plans/boards/*.md` alanına yazıma izin verir. Alt ajanlar board yazamaz; diğer proje/worktree board'ları reddedilir. OpenCode yeniden başlatıldığında aktif olur.

### Sorun giderme

- Panel açılmıyorsa: `doctor.cmd`
- OpenCode'da Browser sekmesi yoksa: Desktop'ı tamamen kapat/aç
- Model bulunamıyorsa: OpenCode'da önce bir provider/model seç; kit varsayılan olarak model pinlemez. Panelde **Modeller** butonunu kullan veya `doctor.cmd` çıktısındaki `Varsayilan model` satırına bak. Test edilmiş OpenCode Go setup'ı için `preset` değerini `opencode-go` yap.
- Alt görev 15 dk+ güncellenmezse panelde `takıldı?` görünür; üst oturumu durdurup OpenCode'u yeniden başlat.
- Kalıcı sorunda `backgroundJobs.sameProviderPolicy` ile aynı sağlayıcıdaki alt görevler foreground çalıştırılabilir; bu paralelliği azaltır.
- Güncelleme rozeti çıkarsa release sayfasını aç veya `update.cmd` çalıştır; SHA256 doğrulanır, `install.cmd` güvenle tekrar çalıştırılabilir.
- Test edilen sürümler: **OpenCode Desktop 2.3.0** ve **OMO-slim 3.0.7**.
- Bildirimler için **Ayarlar → Bildirim izni**; otomatik durdurma opt-in'dir ve eşik + 5 dk sonra çalışır. Otomatik yeniden deneme de opt-in'dir; otomatik durdurmadan 30 sn sonra oturum başına 1 kez çalışır.
- Proje bazlı profil sorunluysa **Modeller → Bu proje için → Proje profilini sıfırla**.
- Diagnostic ZIP: `%USERPROFILE%\.config\opencode\agent-board\diagnostic.cmd`
- Panel write endpoint'leri `X-Panel-Token` ister; panel sayfasını yenilemediysen işlem 403 dönebilir.
- Log: `%USERPROFILE%\.config\opencode\agent-board\guard.log`

### Güvenlik

Kit içinde API key yoktur. `service.json`, `.env`, yedekler ve loglar repoya dahil edilmez. Panel yalnızca `127.0.0.1` üzerinde dinler. Panel write endpoint'leri süreç başına `X-Panel-Token` ister; model listesi sanitize edilir, diagnostic çıktısındaki hassas desenler redakte edilir. `update.cmd` indirdiği ZIP'in SHA256'sını zorunlu olarak doğrular. `OpenCodeOrchestratorKit.exe` varsayılan olarak imzasızdır; public dağıtımdan önce `scripts\sign.ps1` ile imzalanmalıdır. Ayrıntılar: [docs/signing.md](docs/signing.md).

---

## License and assets

MIT. See [LICENSE](LICENSE).

Agent artwork is derived from the open-source OMO-slim repository and is documented in [`agent-board/assets/agents/README.md`](agent-board/assets/agents/README.md).
