#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
PURGE=0
DRY_RUN=0

usage() {
  cat <<'EOF'
OpenCode Orchestrator Kit - macOS/Linux uninstaller

Usage:
  ./uninstall.sh [options]

Options:
  --config-dir <path>  OpenCode config directory (default: ~/.config/opencode)
  --purge              Also remove the installed dashboard, Board Guard, AGENTS.md and orchestrator append
  --dry-run            Print actions without changing anything
  -h, --help           Show this help

The OpenCode config files (opencode.json, oh-my-opencode-slim.json) are kept.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config-dir) CONFIG_DIR="$2"; shift 2 ;;
    --purge) PURGE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

echo "OpenCode Orchestrator Kit - kaldirma"
echo "Hedef: $CONFIG_DIR"

if [[ "$(uname -s)" == "Darwin" ]]; then
  PLIST="$HOME/Library/LaunchAgents/com.ajanpanosu.plist"
  if [[ -f "$PLIST" ]]; then
    run launchctl unload "$PLIST" >/dev/null 2>&1 || true
    run rm -f "$PLIST"
    echo "LaunchAgent kaldirildi."
  fi
  run rm -f "$HOME/Desktop/Ajan Panosu.command"
elif command -v systemctl >/dev/null 2>&1; then
  SERVICE="$HOME/.config/systemd/user/ajan-panosu.service"
  if [[ -f "$SERVICE" ]]; then
    run systemctl --user disable --now ajan-panosu.service >/dev/null 2>&1 || true
    run rm -f "$SERVICE"
    run systemctl --user daemon-reload >/dev/null 2>&1 || true
    echo "systemd servisi kaldirildi."
  fi
  run rm -f "$HOME/.local/share/applications/ajan-panosu.desktop"
fi

if command -v pgrep >/dev/null 2>&1; then
  PANEL_PATTERN="[n]ode .*${CONFIG_DIR}/agent-board/server[.]mjs"
  PIDS="$(pgrep -f "$PANEL_PATTERN" 2>/dev/null || true)"
  if [[ -n "$PIDS" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "[dry-run] kill $PIDS"
    else
      kill $PIDS 2>/dev/null || true
      echo "Panel sureci durduruldu."
    fi
  fi
fi

if [[ $PURGE -eq 1 ]]; then
  run rm -rf "$CONFIG_DIR/agent-board"
  run rm -f "$CONFIG_DIR/plugins/board-guard.js"
  run rm -f "$CONFIG_DIR/AGENTS.md"
  run rm -f "$CONFIG_DIR/oh-my-opencode-slim/orchestrator_append.md"
  echo "Kit dosyalari kaldirildi; opencode.json ve oh-my-opencode-slim.json korundu."
else
  echo "Servis ve kisayollar kaldirildi; config ve panel dosyalari korundu."
  echo "Tamamen kaldirmak icin: ./uninstall.sh --purge"
fi

echo "Kaldirma tamamlandi."
