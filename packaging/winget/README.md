# Winget manifest

This is a release-time template. `scripts/release.ps1` fills `__VERSION__`, `__URL__` and `__SHA256__` into `dist/packaging/`.

## Important limitation

The official winget repository generally expects a signed EXE, MSI or MSIX installer. The kit currently ships a ZIP with `install.cmd`. The ZIP + nested portable manifest here is useful for local testing and for a private winget source, but it may not pass the public winget validation as-is.

To publish publicly:

1. Wrap the kit in a signed EXE or MSI.
2. Change `InstallerType` to the wrapper type.
3. Point `InstallerUrl` to the wrapper and update `InstallerSha256`.
4. Submit the manifest to `microsoft/winget-pkgs`.

Code signing requires a certificate that only the publisher can provide.
