# Contributing

This is a Windows-first v0.1 kit. Keep changes small and testable.

## Before opening a PR

1. Run `doctor.cmd` on a machine with OpenCode Desktop and Node.js.
2. Test `install.cmd` in a disposable config directory if you change the installer:
   `powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -ConfigDir <temp-dir> -NoShortcuts -NoStart`
3. Do not commit `service.json`, `.env`, provider keys, logs, backups or local absolute user paths.
4. Keep user-facing text in Turkish unless the change is specifically for another locale.
5. Update `CHANGELOG.md` and `VERSION` for user-visible changes.

## Scope

In scope:

- installer and doctor reliability,
- OpenCode 2.x compatibility,
- board guard and board lifecycle,
- dashboard usability and security,
- documentation and screenshots.

Out of scope for v0.1:

- agent orchestration runtime,
- launching or controlling agents from the dashboard,
- cloud/SaaS deployment,
- native Desktop UI injection.
