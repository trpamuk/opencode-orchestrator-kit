# OpenCode Orchestrator Kit

**Version:** 0.1.3  
**Platform:** Windows 10/11  
**Status:** early public preview

A one-click Windows bootstrap for a practical multi-agent OpenCode setup:

- [OpenCode Desktop](https://opencode.ai/desktop) as the runtime
- [OMO-slim](https://github.com/alvinunreal/oh-my-opencode-slim) as the orchestrator
- **Ajan Panosu** as a project-aware live dashboard
- **Board Guard** as a write-isolation plugin for task boards

> This is an independent community project. It is not affiliated with or endorsed by OpenCode or OMO-slim.

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
| OMO-slim config | Presets, fallback models, marketplace agents, Companion disabled, 30-minute background-task timeout |
| Global `AGENTS.md` | Board, worktree, review and merge policy |
| `orchestrator_append.md` | Mandatory automatic orchestration workflow |
| `plugins/board-guard.js` | OpenCode V2 plugin that isolates board writes |
| `agent-board/` | Ajan Panosu local dashboard and avatars |
| Startup shortcut | Starts the dashboard server automatically |
| Desktop shortcut | Opens the dashboard in a browser |
| `doctor.cmd` | Checks the installed setup |
| `uninstall.cmd` | Removes shortcuts and stops the dashboard server |

---

## Requirements

Before running the kit, install:

1. **OpenCode Desktop 2.x**
2. **Node.js 22+**
3. A working provider login, normally **OpenCode Go**
4. **Git** (recommended; Board Guard uses it to resolve the repository root)

The kit does **not** install OpenCode Desktop or Node.js. It also does **not** contain provider API keys.

---

## Installation order

This is the important part:

```text
1. Install OpenCode Desktop 2.x
2. Sign in to OpenCode Go (or configure another compatible provider)
3. Install Node.js 22+
4. Extract this kit and run install.cmd
5. Fully quit and reopen OpenCode Desktop
6. Open the dashboard
```

You do **not** need to install OMO-slim manually. The kit writes the OMO-slim plugin configuration and lets OpenCode install the pinned `oh-my-opencode-slim@3.0.7` package on startup.

If OMO-slim is already installed, the installer backs up the existing global config and replaces the orchestration config with the kit version. Existing `opencode.json` provider settings are preserved and merged.

---

## Quick start

1. Download the latest release ZIP.
2. Extract it to a normal folder.
3. Double-click **`install.cmd`**.
4. Wait for the installer to finish.
5. Fully quit and reopen OpenCode Desktop.
6. Open **http://127.0.0.1:43124/**.

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

- Merges the kit plugin, model and default agent into an existing `opencode.json`.
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
- backs up the current config and dashboard,
- swaps the new files into place,
- restarts the dashboard and checks `/health`.

If the staging copy is incomplete, the installer stops before touching the current dashboard.

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
- active task boards, parsed from the project's `.opencode/plans/` area;
- a project selector so two projects never share one board view.

The dashboard keeps child and worktree sessions attached to their parent project, so a worktree subagent cannot disappear from the main project view.

The server binds only to `127.0.0.1:43124`. It reads the local OpenCode service password from `service.json` on the server side and never sends it to the browser.

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

Fully quit and reopen OpenCode Desktop. Some 2.2.x Desktop builds temporarily lose the Browser launcher; a restart restores it. You can use the desktop `Ajan Panosu` shortcut in the meantime.

### Model not found

Sign in to OpenCode Go, or edit the model IDs in:

- `%USERPROFILE%\.config\opencode\opencode.json`
- `%USERPROFILE%\.config\opencode\oh-my-opencode-slim.json`

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
- stop the parent session, then fully restart OpenCode Desktop if the task does not clear.

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

### Full diagnostic

```text
doctor.cmd
```

---

## Security and privacy

- No provider API keys are included in this repository or release.
- `service.json`, `.env`, backups, logs and local ZIPs are excluded by `.gitignore`.
- The dashboard listens on loopback only.
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

**Sürüm:** 0.1.3  
**Platform:** Windows 10/11

Bu kit, OpenCode Desktop + OMO-slim + Ajan Panosu + Board Guard kurulumunu tek tıkla yapar.

### Neden var?

OMO-slim güçlü bir orkestrasyon katmanıdır; ancak OpenCode Desktop içinde proje bazlı, düzgün bir canlı paneli yoktur. Companion yüzen bir durum penceresidir ve çok sayıda proje/oturum açıkken yeterince güvenilir değildir. Bu kit; aktif ajanları, oturumları, board'ları, token/maliyeti gösteren yerel bir panel ve board yazımını izole eden bir guard ekler.

### Kurulum sırası

1. OpenCode Desktop 2.x kur.
2. OpenCode Go hesabına gir.
3. Node.js 22+ kur.
4. ZIP'i çıkar ve `install.cmd` çalıştır.
5. OpenCode Desktop'ı tamamen kapatıp yeniden aç.
6. Paneli aç: `http://127.0.0.1:43124/`

OMO-slim'i ayrıca kurmana gerek yok; kit gerekli config'i yazar ve OpenCode `oh-my-opencode-slim@3.0.7` paketini kendisi yükler.

### Panel

- Yerel adres: `http://127.0.0.1:43124/`
- Masaüstü kısayolu: `Ajan Panosu`
- OpenCode içinde: Review pane → yeni browser sekmesi → aynı URL
- Sunucu Startup'ta otomatik başlar.
- **Alt Görevler** bölümü, oturum içinde çalışan `subagent`/`task` çağrılarını gösterir; 15 dakikadır güncellenmeyenler `takıldı?` olur.

### Board Guard

Sadece projenin `.opencode/plans/current.md` ve `.opencode/plans/boards/*.md` alanına yazıma izin verir. Alt ajanlar board yazamaz; diğer proje/worktree board'ları reddedilir. OpenCode yeniden başlatıldığında aktif olur.

### Sorun giderme

- Panel açılmıyorsa: `doctor.cmd`
- OpenCode'da Browser sekmesi yoksa: Desktop'ı tamamen kapat/aç
- Model bulunamıyorsa: OpenCode Go girişini kontrol et
- Alt görev 15 dk+ güncellenmezse panelde `takıldı?` görünür; üst oturumu durdurup OpenCode'u yeniden başlat.
- Kalıcı sorunda `backgroundJobs.sameProviderPolicy` ile aynı sağlayıcıdaki alt görevler foreground çalıştırılabilir; bu paralelliği azaltır.
- Log: `%USERPROFILE%\.config\opencode\agent-board\guard.log`

### Güvenlik

Kit içinde API key yoktur. `service.json`, `.env`, yedekler ve loglar repoya dahil edilmez. Panel yalnızca `127.0.0.1` üzerinde dinler.

---

## License and assets

MIT. See [LICENSE](LICENSE).

Agent artwork is derived from the open-source OMO-slim repository and is documented in [`agent-board/assets/agents/README.md`](agent-board/assets/agents/README.md).
