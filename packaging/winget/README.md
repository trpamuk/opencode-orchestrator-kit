# Winget manifest

This is a release-time template. `scripts/release.ps1` fills `__VERSION__`, `__URL__` and `__SHA256__` into `dist/packaging/`.

## Important limitation

The ZIP now contains `OpenCodeOrchestratorKit.exe`, a .NET Framework WinExe launcher for the WinForms installer GUI. The manifest uses `InstallerType: zip` with a nested portable EXE. This is useful for local testing and for a private winget source.

The official winget repository generally expects a **trusted code signature**. The launcher is unsigned by default. To publish publicly:

1. Obtain a code-signing certificate.
2. Sign the launcher with `scripts\sign.ps1 -Thumbprint <thumbprint> -File dist\launcher\OpenCodeOrchestratorKit.exe`.
3. Rebuild the release ZIP and update `InstallerSha256`.
4. Submit the manifest to `microsoft/winget-pkgs`.

Code signing requires a certificate that only the publisher can provide. See [`docs/signing.md`](../../docs/signing.md) for the full local and GitHub Actions workflow.
