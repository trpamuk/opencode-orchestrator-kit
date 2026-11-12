# Changelog

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
