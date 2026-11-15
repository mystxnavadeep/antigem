#!/usr/bin/env bash
# ==============================================================================
# antiGem Cloud Workspace - Tailscale Connection Manager
# Authenticates and connects using TAILSCALE_AUTH_KEY only.
# ==============================================================================
set -euo pipefail

echo "============================================================"
echo "  ⚡ antiGem Cloud: Tailscale Authentication"
echo "============================================================"

# Ensure TAILSCALE_AUTH_KEY is provided
if [ -z "${TAILSCALE_AUTH_KEY:-}" ]; then
    echo "  ❌ Error: TAILSCALE_AUTH_KEY environment variable is not set!"
    echo "  Please configure the TAILSCALE_AUTH_KEY repository secret."
    exit 1
fi

# Install Tailscale if not already present on system
if ! command -v tailscale >/dev/null 2>&1; then
    echo "  • Installing Tailscale client..."
    curl -fsSL https://tailscale.com/install.sh | sh >/dev/null 2>&1
fi

# Ensure tailscaled daemon is active with required directories
SUDO_CMD=""
if command -v sudo >/dev/null 2>&1; then
    SUDO_CMD="sudo"
fi

$SUDO_CMD mkdir -p /var/lib/tailscale /run/tailscale
if ! pgrep -x tailscaled >/dev/null 2>&1; then
    echo "  • Starting tailscaled daemon..."
    $SUDO_CMD systemctl start tailscaled 2>/dev/null || \
    $SUDO_CMD service tailscaled start 2>/dev/null || \
    $SUDO_CMD tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock >/dev/null 2>&1 &
    sleep 3
fi

# Build arguments for tailscale up
HOSTNAME="${TAILSCALE_HOSTNAME:-antigem-cloud-runner}"
UP_ARGS=(
    "--authkey=${TAILSCALE_AUTH_KEY}"
    "--hostname=${HOSTNAME}"
    "--accept-routes"
    "--accept-dns=false"
)

# Optional tags if user configured TAILSCALE_TAGS
if [ -n "${TAILSCALE_TAGS:-}" ]; then
    UP_ARGS+=("--advertise-tags=${TAILSCALE_TAGS}")
fi

echo "  • Connecting node to Tailnet..."
# Run tailscale up without leaking authkey to output
set +e
TS_OUTPUT=$($SUDO_CMD tailscale up "${UP_ARGS[@]}" 2>&1)
TS_EXIT=$?
set -e

if [ $TS_EXIT -ne 0 ]; then
    CLEAN_ERR=$(echo "$TS_OUTPUT" | sed "s/${TAILSCALE_AUTH_KEY}/[REDACTED]/g")
    echo "  ❌ Tailscale connection failed: $CLEAN_ERR"
    exit 1
fi

# Verify connectivity and retrieve IP
TAILSCALE_IP="$($SUDO_CMD tailscale ip -4 2>/dev/null || true)"
if [ -z "$TAILSCALE_IP" ]; then
    # Wait up to 15 seconds for IP assignment
    for i in {1..15}; do
        sleep 1
        TAILSCALE_IP="$($SUDO_CMD tailscale ip -4 2>/dev/null || true)"
        if [ -n "$TAILSCALE_IP" ]; then
            break
        fi
    done
fi

if [ -z "$TAILSCALE_IP" ]; then
    echo "  ❌ Error: Failed to obtain Tailscale IP address."
    exit 1
fi

# Output the assigned IP to environment file for subsequent workflow steps
if [ -n "${GITHUB_ENV:-}" ]; then
    echo "TAILSCALE_IP=${TAILSCALE_IP}" >> "$GITHUB_ENV"
fi

echo "  ✅ Tailscale connected successfully!"
echo "  • Runner Tailscale IPv4: ${TAILSCALE_IP}"
echo "============================================================"
