#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
export HOME="$TMP_ROOT/home"
CONFIG_DIR="$HOME/.config/opencode"
PANEL_PORT=43129
PANEL_PID=""

cleanup() {
  if [[ -n "$PANEL_PID" ]] && kill -0 "$PANEL_PID" 2>/dev/null; then
    kill "$PANEL_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$HOME"

bash "$KIT_ROOT/install.sh" --config-dir "$CONFIG_DIR" --no-shortcuts --no-start
test -f "$CONFIG_DIR/opencode.json"
test -f "$CONFIG_DIR/oh-my-opencode-slim.json"
test -f "$CONFIG_DIR/agent-board/server.mjs"

AGENT_BOARD_PORT="$PANEL_PORT" node "$CONFIG_DIR/agent-board/server.mjs" >"$TMP_ROOT/panel.log" 2>&1 &
PANEL_PID=$!

READY=0
for _ in $(seq 1 50); do
  if node -e "fetch('http://127.0.0.1:${PANEL_PORT}/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"; then
    READY=1
    break
  fi
  sleep 0.2
done
if [[ "$READY" -ne 1 ]]; then
  echo "Panel did not start." >&2
  cat "$TMP_ROOT/panel.log" >&2 || true
  exit 1
fi

HEALTH="$(node -e "fetch('http://127.0.0.1:${PANEL_PORT}/health').then(async r=>{process.stdout.write(await r.text()); process.exit(r.ok?0:1)}).catch(()=>process.exit(1))")"
if [[ "$HEALTH" != "ok" ]]; then
  echo "Unexpected health response: $HEALTH" >&2
  exit 1
fi

bash "$KIT_ROOT/uninstall.sh" --config-dir "$CONFIG_DIR" --purge
if kill -0 "$PANEL_PID" 2>/dev/null; then
  echo "Panel process is still running after uninstall." >&2
  exit 1
fi
test -f "$CONFIG_DIR/opencode.json"
test -f "$CONFIG_DIR/oh-my-opencode-slim.json"
test ! -e "$CONFIG_DIR/agent-board"

echo "Linux install/panel/uninstall test passed."
