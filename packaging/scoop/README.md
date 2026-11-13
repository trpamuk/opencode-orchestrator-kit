# Scoop manifest

This is a release-time template. `scripts/release.ps1` fills `__VERSION__`, `__URL__` and `__SHA256__` into `dist/packaging/`.

To use it in a Scoop bucket:

1. Copy `dist/packaging/opencode-orchestrator-kit.json` into your bucket's `bucket/` folder.
2. Commit and push the bucket.
3. Install with `scoop install opencode-orchestrator-kit`.
4. Run `opencode-orchestrator-kit` once.

The manifest exposes `OpenCodeOrchestratorKit.exe` as the `opencode-orchestrator-kit` shim and as a Start Menu shortcut. The EXE opens the WinForms installer GUI.
