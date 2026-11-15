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

# Detect Tailscale IP if not already exported
if [ -z "${TAILSCALE_IP:-}" ]; then
    if command -v tailscale >/dev/null 2>&1; then
        TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || true)"
    fi
fi
TAILSCALE_IP="${TAILSCALE_IP:-127.0.0.1}"

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
export PATH="$HOME_DIR/.local/bin:$HOME_DIR/.gemini/bin:$PATH"

for candidate in "$HOME_DIR/.local/bin/agy" "$HOME_DIR/.gemini/bin/agy" "/usr/local/bin/agy" "$(command -v agy 2>/dev/null || true)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        AGY_BIN="$candidate"
        break
    fi
done

if [ -z "$AGY_BIN" ]; then
    echo "  • Installing Google Antigravity CLI (agy)..."
    mkdir -p "$HOME_DIR/.local/bin"
    if curl -fsSL https://antigravity.google/cli/install.sh | bash; then
        echo "    ✔ Antigravity CLI install script finished."
    else
        echo "    ⚠️ Antigravity CLI installer returned a non-zero exit code."
    fi
    for candidate in "$HOME_DIR/.local/bin/agy" "$HOME_DIR/.gemini/bin/agy" "/usr/local/bin/agy" "$(command -v agy 2>/dev/null || true)"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
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
# Priority: 1. Explicit env SECURITY_TOKEN (GitHub secret), 2. Restored token file, 3. Standard default 'antigemcloud1'
TOKEN_FILE="$HOME_DIR/.antigem_bridge/csrf_token.txt"
TOKEN=""
if [ -n "${SECURITY_TOKEN:-}" ] && [ "${#SECURITY_TOKEN}" -eq 12 ]; then
    TOKEN="$SECURITY_TOKEN"
elif [ -f "$TOKEN_FILE" ]; then
    TOKEN="$(cat "$TOKEN_FILE" | tr -d '[:space:]')"
fi
if [ -z "${TOKEN:-}" ] || [ "${#TOKEN}" -ne 12 ]; then
    TOKEN="antigemcloud1"
fi
mkdir -p "$(dirname "$TOKEN_FILE")"
echo "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"

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

# 7. Configure Network Forwarding for Hub Port 1235
# 'agy --hub' listens exclusively on 127.0.0.1:1235.
# We forward incoming connections from the Tailscale IP on port 1235 to 127.0.0.1:1235.
if command -v sudo >/dev/null 2>&1; then
    sudo sysctl -w net.ipv4.conf.all.route_localnet=1 >/dev/null 2>&1 || true
    sudo sysctl -w net.ipv4.conf.default.route_localnet=1 >/dev/null 2>&1 || true
    sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    sudo iptables -t nat -A PREROUTING -p tcp --dport 1235 -j DNAT --to-destination 127.0.0.1:1235 2>/dev/null || true
fi

# Start socat forwarding proxy on Tailscale IP
if command -v socat >/dev/null 2>&1; then
    if [ "$TAILSCALE_IP" != "127.0.0.1" ]; then
        echo "  • Starting socat forward: ${TAILSCALE_IP}:1235 -> 127.0.0.1:1235..."
        pkill -f "socat.*1235" 2>/dev/null || true
        nohup socat TCP-LISTEN:1235,bind="$TAILSCALE_IP",fork,reuseaddr TCP:127.0.0.1:1235 >> "$LOGS_DIR/hub-forward.log" 2>&1 &
    fi
fi

# 8. Wait and Verify Health of Bridge (1234) and Hub (1235)
echo "  • Waiting for Bridge to become healthy on port 1234..."
UP=false
for i in {1..30}; do
    if curl -s -f http://127.0.0.1:1234/api/health >/dev/null 2>&1; then
        UP=true
        break
    fi
    sleep 1
done

if [ "$UP" = true ]; then
    echo "    ✔ Bridge is ONLINE on port 1234!"
else
    echo "    ❌ Error: Bridge did not answer within 30 seconds."
    echo "    Recent log output:"
    tail -n 25 "$BRIDGE_LOG" 2>/dev/null || true
    exit 1
fi

echo "  • Waiting for AGY Hub on port 1235..."
HUB_UP=false
for i in {1..30}; do
    if curl -s -m 2 http://127.0.0.1:1235/ >/dev/null 2>&1 || (exec 3<>/dev/tcp/127.0.0.1/1235) 2>/dev/null; then
        exec 3<&- 2>/dev/null || true
        exec 3>&- 2>/dev/null || true
        HUB_UP=true
        break
    fi
    sleep 1
done

if [ "$HUB_UP" = true ]; then
    echo "    ✔ AGY Hub is ONLINE on port 1235!"
else
    echo "    ⚠️ Warning: AGY Hub not answering on 127.0.0.1:1235 yet."
fi

# Test Tailscale IP reachability on port 1235
if [ "$TAILSCALE_IP" != "127.0.0.1" ]; then
    echo "  • Verifying Tailscale reachability on port 1235..."
    if curl -s -m 3 "http://${TAILSCALE_IP}:1235/" >/dev/null 2>&1 || (exec 3<>/dev/tcp/${TAILSCALE_IP}/1235) 2>/dev/null; then
        exec 3<&- 2>/dev/null || true
        exec 3>&- 2>/dev/null || true
        echo "    ✔ Tailscale Port 1235 is OPEN and forward is active!"
    else
        echo "    ⚠️ Notice: Port 1235 may still be initializing."
    fi
fi

# 9. Start Browser Plugin Extension Host if Node.js is present
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

echo ""
echo "============================================================"
echo "  🎉 antiGem Services are LIVE!"
echo "============================================================"
echo "  • IDE Bridge URL:  http://${TAILSCALE_IP}:1234"
echo "  • AGY Hub URL:     http://${TAILSCALE_IP}:1235"
echo "  • SSH Server:      ${TAILSCALE_IP}:22"
echo "  • SSH User:        $CURRENT_USER"
echo "  • Security Token:  $TOKEN"
echo "============================================================"
