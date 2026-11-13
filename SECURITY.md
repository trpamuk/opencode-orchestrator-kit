# Security

## Scope

This kit is a local Windows bootstrap for OpenCode, OMO-slim, a local dashboard and an OpenCode board-guard plugin.

- The dashboard binds to `127.0.0.1` only.
- The kit does not contain provider API keys, OpenCode service passwords or user secrets.
- Provider authentication is performed by the user through OpenCode.
- Local runtime state such as `service.json`, `.env`, logs and backups is excluded by `.gitignore`.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use GitHub's private vulnerability reporting for this repository, or contact the maintainer through the repository profile.

Include:

- affected version,
- Windows version,
- reproduction steps,
- expected and actual behavior,
- whether secrets or local files were exposed.

## Hardening notes

- Keep the dashboard on loopback.
- Panel write endpoints require a per-process `X-Panel-Token` injected into the panel HTML.
- The model list is sanitized; provider API keys and settings are never sent to the browser.
- The diagnostic endpoint redacts common secret patterns from config summaries and log tails.
- Project profiles are written only to `<project>\.opencode\oh-my-opencode-slim.json` after validating the project directory.
- `update.cmd` verifies the release SHA256 before extracting or running the installer.
- `OpenCodeOrchestratorKit.exe` is unsigned by default. Sign it with a trusted certificate via `scripts\sign.ps1` before public distribution.
- Do not expose port `43124` to a LAN or the internet without an authenticated reverse proxy.
- Review third-party OpenCode plugins before installing them.
- Rotate provider credentials if you suspect exposure.
