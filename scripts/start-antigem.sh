#!/usr/bin/env bash
# ==============================================================================
# antiGem Cloud Workspace - Service Supervisor & Starter
# Builds (if needed) and starts antiGem IDE Server, AGY Hub, and Extension Host.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CURRENT_USER="$(whoami)"
HOME_DIR="${HOME:-/home/$CURRENT_USER}"
LOGS_DIR="$HOME_DIR/logs"
BIN_DIR="$PROJECT_ROOT/bin"
mkdir -p "$LOGS_DIR" "$BIN_DIR" "$HOME_DIR/projects" "$HOME_DIR/.antigem/uploads"

echo "============================================================"
echo "  ⚡ antiGem Cloud: Starting Services"
echo "============================================================"

# 1. Compile agy_ide_bridge binary if not present
BRIDGE_BIN="$BIN_DIR/agy_ide_bridge"
if [ ! -f "$BRIDGE_BIN" ]; then
    echo "  • Compiling antiGem Go IDE Bridge..."
    cp "$PROJECT_ROOT/version.json" "$PROJECT_ROOT/agy_ide_bridge/pkg/buildinfo/version.json"
    (
        cd "$PROJECT_ROOT/agy_ide_bridge"
        CGO_ENABLED=0 go build -ldflags="-s -w" -o "$BRIDGE_BIN" main.go
    )
    chmod +x "$BRIDGE_BIN"
    echo "    ✔ Bridge compiled successfully: $BRIDGE_BIN"
fi

# 2. Check and locate Antigravity CLI binary
AGY_BIN=""
for candidate in "$HOME_DIR/.local/bin/agy" "$HOME_DIR/.gemini/bin/agy" "/usr/local/bin/agy" "$(command -v agy 2>/dev/null || true)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        AGY_BIN="$candidate"
        break
    fi
done

if [ -z "$AGY_BIN" ]; then
    echo "  • Installing Google Antigravity CLI (agy)..."
    curl -fsSL https://antigravity.google/cli/install.sh | bash >/dev/null 2>&1 || true
    for candidate in "$HOME_DIR/.local/bin/agy" "$HOME_DIR/.gemini/bin/agy"; do
        if [ -x "$candidate" ]; then
            AGY_BIN="$candidate"
            break
        fi
    done
fi

if [ -n "$AGY_BIN" ]; then
    echo "    ✔ Detected Antigravity CLI: $AGY_BIN"
else
    echo "    ⚠️ Warning: agy binary not detected. Bridge will run in standalone IDE mode."
fi

# 3. Check for optional AI CLIs (Claude Code, OpenCode, Codex)
CLAUDE_FLAG="--no-claude"
if command -v claude >/dev/null 2>&1; then
    CLAUDE_FLAG="--claude-bin=$(command -v claude)"
elif [ -x "$HOME_DIR/.local/bin/claude" ]; then
    CLAUDE_FLAG="--claude-bin=$HOME_DIR/.local/bin/claude"
fi

OPENCODE_FLAG="--no-opencode"
if command -v opencode >/dev/null 2>&1; then
    OPENCODE_FLAG="--opencode-bin=$(command -v opencode)"
elif [ -x "$HOME_DIR/.opencode/bin/opencode" ]; then
    OPENCODE_FLAG="--opencode-bin=$HOME_DIR/.opencode/bin/opencode"
fi

CODEX_FLAG="--no-codex"
if command -v codex >/dev/null 2>&1; then
    CODEX_FLAG="--codex-bin=$(command -v codex)"
elif [ -x "$HOME_DIR/.local/bin/codex" ]; then
    CODEX_FLAG="--codex-bin=$HOME_DIR/.local/bin/codex"
fi

# 4. Resolve 12-char Security Token
TOKEN_FILE="$HOME_DIR/.antigem_bridge/csrf_token.txt"
if [ -f "$TOKEN_FILE" ]; then
    TOKEN="$(cat "$TOKEN_FILE" | tr -d '[:space:]')"
fi
if [ -z "${TOKEN:-}" ] || [ "${#TOKEN}" -lt 12 ]; then
    TOKEN="$(tr -dc 'a-z0-9' < /dev/urandom | head -c 12 || echo 'n6mjyd8v6nzp')"
    mkdir -p "$(dirname "$TOKEN_FILE")"
    echo "$TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
fi

# 5. Build Bridge Command Arguments
BRIDGE_ARGS=(
    "-f"
    "--token=$TOKEN"
    "-p=1234"
    "--hub-port=1235"
    "--bind=0.0.0.0"
    "--tz-offset=0"
    "-d=$HOME_DIR/projects"
    "$CLAUDE_FLAG"
    "$OPENCODE_FLAG"
    "$CODEX_FLAG"
)
if [ -n "$AGY_BIN" ]; then
    BRIDGE_ARGS+=("--bin=$AGY_BIN")
else
    BRIDGE_ARGS+=("--no-hub")
fi

# 6. Launch Bridge in background
BRIDGE_LOG="$LOGS_DIR/bridge.log"
echo "  • Launching antiGem IDE Bridge on :1234 (Hub on :1235)..."
nohup "$BRIDGE_BIN" "${BRIDGE_ARGS[@]}" >> "$BRIDGE_LOG" 2>&1 &
BRIDGE_PID=$!
echo "$BRIDGE_PID" > "$HOME_DIR/.server.pid"

# 7. Wait and Verify Health
echo "  • Waiting for bridge to become healthy..."
UP=false
for i in {1..30}; do
    if curl -s -f http://127.0.0.1:1234/api/health >/dev/null 2>&1; then
        UP=true
        break
    fi
    sleep 1
done

if [ "$UP" = true ]; then
    echo "    ✔ Bridge is ONLINE and healthy!"
else
    echo "    ❌ Error: Bridge did not answer within 30 seconds."
    echo "    Recent log output:"
    tail -n 20 "$BRIDGE_LOG" 2>/dev/null || true
    exit 1
fi

# 8. Start Browser Plugin Extension Host if Node.js is present
if command -v node >/dev/null 2>&1; then
    EXT_HOST_FILE="$PROJECT_ROOT/app/src/main/assets/browser-runtime/extension-host.mjs"
    if [ -f "$EXT_HOST_FILE" ]; then
        echo "  • Starting browser plugin extension host on :8865..."
        mkdir -p "$HOME_DIR/.antigem/browser-extensions" "$HOME_DIR/extensions"
        nohup node --experimental-vm-modules "$EXT_HOST_FILE" \
            --serve --port 8865 \
            --root "$HOME_DIR/.antigem/browser-extensions" \
            --extra-root "$HOME_DIR/extensions" \
            --device-id "cloud-runner-$(hostname)" \
            --bridge-url "http://127.0.0.1:8765" >> "$LOGS_DIR/extension-host.log" 2>&1 &
        echo "    ✔ Extension host running."
    fi
fi

TAILSCALE_IP_DISPLAY="${TAILSCALE_IP:-127.0.0.1}"
echo ""
echo "============================================================"
echo "  🎉 antiGem Services are LIVE!"
echo "============================================================"
echo "  • IDE Bridge URL:  http://${TAILSCALE_IP_DISPLAY}:1234"
echo "  • AGY Hub URL:     http://${TAILSCALE_IP_DISPLAY}:1235"
echo "  • SSH Server:      ${TAILSCALE_IP_DISPLAY}:22"
echo "  • SSH User:        $CURRENT_USER"
echo "  • Security Token:  $TOKEN"
echo "============================================================"
