#!/usr/bin/env bash
set -u

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
FAILED=0

usage() {
  cat <<'EOF'
OpenCode Orchestrator Kit - macOS/Linux doctor

Usage:
  ./doctor.sh [options]

Options:
  --config-dir <path>  OpenCode config directory (default: ~/.config/opencode)
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config-dir) CONFIG_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

AGENT_BOARD_DIR="$CONFIG_DIR/agent-board"

check() {
  local name="$1" ok="$2" detail="${3:-}"
  if [[ "$ok" == "1" ]]; then
    printf '[OK]   %s%s\n' "$name" "${detail:+ - $detail}"
  else
    printf '[FAIL] %s%s\n' "$name" "${detail:+ - $detail}"
    FAILED=$((FAILED + 1))
  fi
}

info() {
  printf '[INFO] %s\n' "$1"
}

echo "OpenCode Orchestrator Kit - doctor"

NODE_BIN="$(command -v node 2>/dev/null || true)"
if [[ -n "$NODE_BIN" ]]; then
  NODE_VERSION="$("$NODE_BIN" -v 2>/dev/null | sed 's/^v//')"
  NODE_MAJOR="${NODE_VERSION%%.*}"
  if [[ "$NODE_MAJOR" =~ ^[0-9]+$ ]] && [[ "$NODE_MAJOR" -ge 22 ]]; then
    check "Node.js" 1 "$NODE_VERSION ($NODE_BIN)"
  else
    check "Node.js 22+" 0 "$NODE_VERSION ($NODE_BIN)"
  fi
else
  check "Node.js" 0 "https://nodejs.org/"
fi

if command -v opencode >/dev/null 2>&1; then
  check "OpenCode CLI" 1 "$(opencode --version 2>/dev/null || command -v opencode)"
else
  check "OpenCode CLI" 0 "PATH'te yok; Desktop ile devam edilebilir"
fi

check "opencode.json" "$([[ -f "$CONFIG_DIR/opencode.json" ]] && echo 1 || echo 0)"
check "oh-my-opencode-slim.json" "$([[ -f "$CONFIG_DIR/oh-my-opencode-slim.json" ]] && echo 1 || echo 0)"
check "AGENTS.md" "$([[ -f "$CONFIG_DIR/AGENTS.md" ]] && echo 1 || echo 0)"
check "board-guard.js" "$([[ -f "$CONFIG_DIR/plugins/board-guard.js" ]] && echo 1 || echo 0)"
check "agent-board/server.mjs" "$([[ -f "$AGENT_BOARD_DIR/server.mjs" ]] && echo 1 || echo 0)"
check "agent-board/index.html" "$([[ -f "$AGENT_BOARD_DIR/index.html" ]] && echo 1 || echo 0)"

if [[ -n "$NODE_BIN" && -f "$CONFIG_DIR/opencode.json" ]]; then
  PLUGIN_OK="$("$NODE_BIN" -e '
    const fs = require("fs");
    try {
      const config = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      console.log((config.plugins || []).includes("oh-my-opencode-slim@3.0.7") ? "1" : "0");
    } catch {
      console.log("0");
    }
  ' "$CONFIG_DIR/opencode.json" 2>/dev/null || echo 0)"
  check "OMO-slim plugin" "$PLUGIN_OK" "oh-my-opencode-slim@3.0.7"
fi

if [[ -n "$NODE_BIN" && -f "$CONFIG_DIR/oh-my-opencode-slim.json" ]]; then
  OMO_COMPANION="$("$NODE_BIN" -e '
    const fs = require("fs");
    try {
      const config = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      console.log(config.companion?.enabled === false ? "1" : "0");
    } catch {
      console.log("0");
    }
  ' "$CONFIG_DIR/oh-my-opencode-slim.json" 2>/dev/null || echo 0)"
  check "Companion kapali" "$OMO_COMPANION" "enabled=false"

  OMO_SCHEMA="$("$NODE_BIN" -e '
    const fs = require("fs");
    try {
      const config = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      console.log(String(config.$schema || "").includes("3.0.7") ? "1" : "0");
    } catch {
      console.log("0");
    }
  ' "$CONFIG_DIR/oh-my-opencode-slim.json" 2>/dev/null || echo 0)"
  check "OMO-slim schema 3.0.7" "$OMO_SCHEMA"

  OMO_PRESET="$("$NODE_BIN" -e '
    const fs = require("fs");
    try {
      const config = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      console.log(config.preset || "");
    } catch {
      console.log("");
    }
  ' "$CONFIG_DIR/oh-my-opencode-slim.json" 2>/dev/null || true)"
  if [[ "$OMO_PRESET" == "session" || "$OMO_PRESET" == "opencode-go" ]]; then
    check "OMO preset" 1 "preset=$OMO_PRESET"
  else
    check "OMO preset" 0 "preset=${OMO_PRESET:-?}"
  fi
fi

if command -v curl >/dev/null 2>&1; then
  HEALTH="$(curl -fsS --max-time 5 http://127.0.0.1:43124/health 2>/dev/null || true)"
  check "Panel health" "$([[ "$HEALTH" == "ok" ]] && echo 1 || echo 0)" "http://127.0.0.1:43124/"

  if [[ -n "$NODE_BIN" ]]; then
    SETUP="$(curl -fsS --max-time 10 http://127.0.0.1:43124/api/setup 2>/dev/null || true)"
    MODEL="$("$NODE_BIN" -e '
      let data = "";
      process.stdin.on("data", (chunk) => (data += chunk));
      process.stdin.on("end", () => {
        try {
          const setup = JSON.parse(data);
          console.log(setup.hasModel ? setup.defaultModel : "");
        } catch {
          console.log("");
        }
      });
    ' <<<"$SETUP" 2>/dev/null || true)"
    MODEL_HINT="OpenCode'da bir provider/model sec"
    check "Varsayilan model" "$([[ -n "$MODEL" ]] && echo 1 || echo 0)" "${MODEL:-$MODEL_HINT}"
  fi
else
  check "Panel health" 0 "curl bulunamadi"
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  check "LaunchAgent" "$([[ -f "$HOME/Library/LaunchAgents/com.ajanpanosu.plist" ]] && echo 1 || echo 0)"
  check "Desktop shortcut" "$([[ -f "$HOME/Desktop/Ajan Panosu.command" ]] && echo 1 || echo 0)"
elif command -v systemctl >/dev/null 2>&1; then
  check "systemd service" "$([[ -f "$HOME/.config/systemd/user/ajan-panosu.service" ]] && echo 1 || echo 0)"
  check "Desktop shortcut" "$([[ -f "$HOME/.local/share/applications/ajan-panosu.desktop" ]] && echo 1 || echo 0)"
fi

if [[ -f "$AGENT_BOARD_DIR/guard.log" ]]; then
  check "Board guard log" 1 "$(tail -n 1 "$AGENT_BOARD_DIR/guard.log")"
else
  info "Board guard log henuz yok (ilk board yaziminda olusur)."
fi

echo ""
if [[ "$FAILED" -eq 0 ]]; then
  echo "Sonuc: sorun gorunmuyor."
  exit 0
fi
echo "Sonuc: $FAILED kontrol basarisiz."
exit 1
