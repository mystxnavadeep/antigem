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

# Ensure tailscaled daemon is active
if ! pgrep -x tailscaled >/dev/null 2>&1; then
    echo "  • Starting tailscaled daemon..."
    if command -v sudo >/dev/null 2>&1; then
        sudo tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock >/dev/null 2>&1 &
    else
        tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock >/dev/null 2>&1 &
    fi
    sleep 3
fi

# Build arguments for tailscale up
# Uses --ephemeral so runner nodes are automatically removed upon termination
HOSTNAME="${TAILSCALE_HOSTNAME:-antigem-cloud-$(cat /etc/hostname 2>/dev/null || echo runner)}"
UP_ARGS=(
    "--authkey=${TAILSCALE_AUTH_KEY}"
    "--hostname=${HOSTNAME}"
    "--accept-routes"
    "--accept-dns=false"
    "--ephemeral=true"
)

# Optional tags if user configured TAILSCALE_TAGS
if [ -n "${TAILSCALE_TAGS:-}" ]; then
    UP_ARGS+=("--advertise-tags=${TAILSCALE_TAGS}")
fi

echo "  • Connecting node to Tailnet..."
# Run tailscale up without leaking authkey to output
SUDO_CMD=""
if command -v sudo >/dev/null 2>&1; then
    SUDO_CMD="sudo"
fi

set +x
$SUDO_CMD tailscale up "${UP_ARGS[@]}" >/dev/null 2>&1 || {
    # If ephemeral flag fails (e.g. tag-enforced auth key without ephemeral permitted), retry without --ephemeral
    echo "  ℹ Retrying without --ephemeral flag..."
    RETRY_ARGS=("${UP_ARGS[@]/--ephemeral=true/}")
    $SUDO_CMD tailscale up "${RETRY_ARGS[@]}" >/dev/null 2>&1
}

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
