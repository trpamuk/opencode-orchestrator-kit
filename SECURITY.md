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
- Do not expose port `43124` to a LAN or the internet without an authenticated reverse proxy.
- Review third-party OpenCode plugins before installing them.
- Rotate provider credentials if you suspect exposure.
