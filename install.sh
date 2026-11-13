#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
NO_START=0
NO_SHORTCUTS=0
DRY_RUN=0
MODEL=""

usage() {
  cat <<'EOF'
OpenCode Orchestrator Kit - macOS/Linux installer

Usage:
  ./install.sh [options]

Options:
  --config-dir <path>  OpenCode config directory (default: ~/.config/opencode)
  --model <provider/model>  Set the main model in opencode.json
  --no-start           Do not start the dashboard service
  --no-shortcuts       Do not create a desktop shortcut
  --dry-run            Print actions without writing
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config-dir) CONFIG_DIR="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --no-start) NO_START=1; shift ;;
    --no-shortcuts) NO_SHORTCUTS=1; shift ;;
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

echo "OpenCode Orchestrator Kit - kurulum"
echo "Hedef: $CONFIG_DIR"

if ! command -v node >/dev/null 2>&1; then
  echo "HATA: Node.js 22+ gerekli." >&2
  exit 1
fi
NODE_BIN="$(command -v node)"
echo "Node: $NODE_BIN"

if command -v opencode >/dev/null 2>&1; then
  echo "OpenCode CLI: $(command -v opencode)"
else
  echo "UYARI: opencode PATH'te yok. Desktop uzerinden devam edilebilir."
fi

run mkdir -p "$CONFIG_DIR/plugins" "$CONFIG_DIR/agent-board" "$CONFIG_DIR/oh-my-opencode-slim"
run node "$KIT_ROOT/scripts/install-config.mjs" opencode "$CONFIG_DIR/opencode.json" "$KIT_ROOT/config/opencode.json"
run node "$KIT_ROOT/scripts/install-config.mjs" omo "$CONFIG_DIR/oh-my-opencode-slim.json" "$KIT_ROOT/config/oh-my-opencode-slim.json"

if [[ -n "$MODEL" ]]; then
  if [[ "$MODEL" != */* ]]; then
    echo "HATA: Model formati gecersiz. Ornek: provider/model" >&2
    exit 1
  fi
  run node "$KIT_ROOT/scripts/install-config.mjs" model "$CONFIG_DIR/opencode.json" "$MODEL"
  echo "Model: $MODEL"
else
  echo "Model: mevcut secim korunuyor (OpenCode icinden degistirilebilir)."
fi

run cp "$KIT_ROOT/config/AGENTS.md" "$CONFIG_DIR/AGENTS.md"
run cp "$KIT_ROOT/config/orchestrator_append.md" "$CONFIG_DIR/oh-my-opencode-slim/orchestrator_append.md"
run cp "$KIT_ROOT/plugins/board-guard.js" "$CONFIG_DIR/plugins/board-guard.js"
run cp -R "$KIT_ROOT/agent-board/." "$CONFIG_DIR/agent-board/"
echo "Config ve panel dosyalari yazildi."

if [[ $NO_SHORTCUTS -eq 0 && $DRY_RUN -eq 0 ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    SHORTCUT="$HOME/Desktop/Ajan Panosu.command"
    cat > "$SHORTCUT" <<'EOF'
#!/bin/bash
open http://127.0.0.1:43124/
EOF
    chmod +x "$SHORTCUT"
    echo "Masaustu kisayolu: $SHORTCUT"
  elif command -v xdg-open >/dev/null 2>&1; then
    APPS="$HOME/.local/share/applications"
    mkdir -p "$APPS"
    cat > "$APPS/ajan-panosu.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Ajan Panosu
Exec=xdg-open http://127.0.0.1:43124/
Terminal=false
EOF
    echo "Masaustu kisayolu: $APPS/ajan-panosu.desktop"
  fi
fi

if [[ $NO_START -eq 0 && $DRY_RUN -eq 0 ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    PLIST="$HOME/Library/LaunchAgents/com.ajanpanosu.plist"
    mkdir -p "$(dirname "$PLIST")"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.ajanpanosu</string>
  <key>ProgramArguments</key>
  <array>
    <string>$NODE_BIN</string>
    <string>$CONFIG_DIR/agent-board/server.mjs</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
EOF
    launchctl unload "$PLIST" >/dev/null 2>&1 || true
    launchctl load "$PLIST" >/dev/null 2>&1 || true
    echo "Panel servisi: launchd ($PLIST)"
  elif command -v systemctl >/dev/null 2>&1; then
    SERVICE_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SERVICE_DIR"
    cat > "$SERVICE_DIR/ajan-panosu.service" <<EOF
[Unit]
Description=Ajan Panosu
[Service]
ExecStart=$NODE_BIN $CONFIG_DIR/agent-board/server.mjs
Restart=on-failure
[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user enable --now ajan-panosu.service >/dev/null 2>&1 || true
    echo "Panel servisi: systemd --user (ajan-panosu.service)"
  else
    nohup "$NODE_BIN" "$CONFIG_DIR/agent-board/server.mjs" >/dev/null 2>&1 &
    echo "Panel arka planda baslatildi."
  fi
  if command -v curl >/dev/null 2>&1; then
    sleep 1
    curl -fsS http://127.0.0.1:43124/health >/dev/null 2>&1 && echo "Panel health: ok" || echo "UYARI: Panel health dogrulanamadi."
  fi
fi

echo ""
echo "Kurulum tamamlandi."
echo "1. OpenCode Desktop'i tamamen kapatip yeniden ac."
echo "2. OpenCode'da istedigin provider/model'i sec."
echo "3. Panel: http://127.0.0.1:43124/"
echo "4. Sorun olursa: doctor (Windows) veya panel /health."
