# Changelog

## 0.4.6 - 2026-11-13

- `update.ps1` now accepts `-Version` for installing or rolling back to a specific release
- The updater verifies that the release tag, asset name, ZIP `VERSION` and panel `VERSION` all match before installing
- Added `scripts/verify-release.ps1` to verify local or online release assets, SHA256, versions, required files, launcher signature and manifests
- CI now runs the release verifier after building the package
- Documented release verification in `README.md` and `docs/signing.md`

## 0.4.5 - 2026-11-13

- `scripts/sign.ps1` now supports certificate thumbprints and PFX files, verifies the signer, and can accept self-signed test signatures with `-AllowUntrusted`
- `scripts/release.ps1` can sign the launcher during a release and rejects a `-Version` that does not match `VERSION`
- Added an end-to-end code-signing smoke test to CI
- Added the optional `Release` GitHub Actions workflow for signed builds using `WINDOWS_CERT_PFX_BASE64` and `WINDOWS_CERT_PASSWORD`
- Added `docs/signing.md` with certificate, PFX, secret, verification and Winget submission steps
- `update.cmd` and `update.ps1` remain SHA256-verified; `VERSION` and the launcher version stay in sync

## 0.4.4 - 2026-11-13

- Launcher file version now follows `VERSION` automatically
- Fixed the GUI installer argument variable to avoid PowerShell's automatic `$args`
- Re-verified OpenCode Desktop 2.3.0 and OMO-slim 3.0.7 compatibility

## 0.4.3 - 2026-11-13

- Added `OpenCodeOrchestratorKit.exe`, a .NET Framework WinExe launcher for the GUI installer
- Added `update.cmd` / `update.ps1` with GitHub latest-release download, SHA256 verification and safe reinstall
- Added `scripts/build-launcher.ps1` and `scripts/sign.ps1` for build and code-signing workflows
- Scoop and Winget manifests now target the EXE launcher; `winget validate` passes
- Verified compatibility with OpenCode Desktop 2.3.0 and OMO-slim 3.0.7
- Updated docs to state OpenCode Desktop 2.3.x is the tested version
- CI now builds the launcher, validates the Winget manifest and parses the updater/signing scripts

## 0.4.2 - 2026-11-13

- Added opt-in auto-retry after auto-stop: one retry prompt 30 seconds later, once per stuck session

## 0.4.1 - 2026-11-13

- Session detail now fetches child sessions directly from OpenCode, so the lineage tree is complete even when the project session list is truncated

## 0.4.0 - 2026-11-13

- Added panel version display and GitHub release update check
- Added a per-process panel token for all write endpoints
- Added a live model health test (temporary session, tiny prompt, automatic cleanup)
- Added primary + fallback model chains per agent
- Added `session` / `opencode-go` preset switching from the dashboard
- Added per-project OMO profiles written to `<project>/.opencode/oh-my-opencode-slim.json`
- Added configurable stuck threshold, opt-in auto-stop and Web Notifications
- Added session detail live refresh, tool filter, copy error, lineage tree and retry
- Added agent analytics, Board Guard log viewer and board archive button
- Added a redacted diagnostic JSON endpoint and ZIP script
- Added a WinForms installer GUI with searchable model selection
- Added a macOS/Linux `install.sh` installer and config merge helper
- Added `scripts/release.ps1`, SHA256 checksums, Scoop manifest and Winget template
- Added GitHub Actions CI for syntax, installer, config merge and server smoke tests
- Documented the Winget signing limitation and the macOS/Linux experimental status

## 0.3.0 - 2026-11-12

- Added model selection to the installer: lists models from the running OpenCode service, preserves the current model, supports `-NoModelPrompt` and `-Model "provider/model"`
- Added a first-run warning when no default model is selected
- Added a dashboard **Modeller** dialog for per-agent model profiles with a timestamped config backup
- The model list is sanitized; provider API keys and settings never reach the browser
- Added a dashboard **Detay** dialog with recent tool calls, errors, model, tokens and cost
- Added secret redaction to the session detail output
- `doctor.cmd` now checks the default model and reports `Varsayilan model`

## 0.2.0 - 2026-11-12

- Removed the OpenCode Go requirement
- The kit no longer pins a model in `opencode.json`
- Added a model-agnostic `session` preset that inherits the model selected in OpenCode
- Kept the tested `opencode-go` preset as an optional alternative
- The installer preserves the user's selected model
- `doctor.cmd` accepts both `session` and `opencode-go` presets
- Documented per-agent model overrides and the Observer vision requirement

## 0.1.5 - 2026-11-12

- Added a **Durdur** button to stuck session and subagent-task cards
- The button asks for confirmation and calls OpenCode's session interrupt
- Server-side guard: only active sessions with a running subagent task can be interrupted
- Same-origin check on `POST /api/interrupt`
- Documented that a stopped fixer may leave uncommitted changes; check `git status` before retrying

## 0.1.4 - 2026-11-12

- Hide the legacy `current.md` board when it is only an index without a task table

## 0.1.3 - 2026-11-12

- Added **Alt Görevler** to the dashboard: running `subagent`/`task` tool calls are shown even when no child session exists
- Added a **takıldı?** state for sessions and subagent tasks with no update for 15 minutes
- Added a stuck count to the header and project selector
- The active filter now keeps stale active sessions and sessions with running subagent tasks visible
- Child and worktree sessions are attached to their parent project
- Added `backgroundJobs.wallClockTimeoutMs: 1800000` to the OMO-slim config as a 30-minute safety net
- Documented the native background-subagent hang and the dashboard warning path

## 0.1.2 - 2026-11-12

- Made the installer safe to re-run
- Stop the dashboard before replacing its files
- Stage and validate the dashboard before swapping it in
- Preserve the existing `guard.log`
- Back up the current dashboard directory
- Keep the current dashboard intact if staging fails
- Added a README section explaining safe re-installation

## 0.1.1 - 2026-11-12

- Rewrote the main README for a global English-speaking audience
- Documented the installation order: OpenCode Desktop -> provider login -> Node.js -> kit
- Clarified that the kit configures OMO-slim automatically; no manual OMO-slim install is required
- Added the project motivation: OMO-slim has no first-class project-aware Desktop dashboard
- Added a Turkish quick-reference section
- Added SECURITY.md and CONTRIBUTING.md
- Removed a personal Windows path from the dashboard README

## 0.1.0 - 2026-11-12

- Windows one-click installer (`install.cmd`)
- OpenCode + OMO-slim 3.0.7 config bootstrap
- Global `AGENTS.md` and orchestrator policy
- Board guard OpenCode V2 plugin
- Ajan Panosu local dashboard with avatars, sessions, boards, tokens and cost
- Startup and desktop shortcuts
- `doctor.cmd` diagnostics
- `uninstall.cmd` shortcut/process cleanup
