#!/usr/bin/env bash
# ==============================================================================
# antiGem Cloud Workspace - SSH Server Setup
# Configures and starts OpenSSH server on the GitHub Actions Ubuntu runner.
# ==============================================================================
set -euo pipefail

SSH_PORT="${SSH_PORT:-22}"
CURRENT_USER="$(whoami)"
HOME_DIR="${HOME:-/home/$CURRENT_USER}"
SSH_DIR="$HOME_DIR/.ssh"

echo "============================================================"
echo "  ⚡ antiGem Cloud: Configuring OpenSSH Server"
echo "============================================================"
echo "  • User: $CURRENT_USER"
echo "  • Home: $HOME_DIR"
echo "  • Port: $SSH_PORT"

# 1. Install openssh-server if not present
if ! command -v sshd >/dev/null 2>&1; then
    echo "  • Installing OpenSSH server..."
    if command -v sudo >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y -qq openssh-server
    else
        apt-get update -qq && apt-get install -y -qq openssh-server
    fi
fi

# 2. Configure SSH directory and authorized_keys
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
touch "$SSH_DIR/authorized_keys"
chmod 600 "$SSH_DIR/authorized_keys"

# Support external public key from secret if provided
if [ -n "${SSH_AUTHORIZED_KEY:-}" ]; then
    echo "$SSH_AUTHORIZED_KEY" >> "$SSH_DIR/authorized_keys"
    echo "  • User-provided SSH public key added to authorized_keys."
fi

# 3. Check for existing keypair or generate a persistent one
KEY_FILE="$SSH_DIR/antigem_ed25519"
if [ ! -f "$KEY_FILE" ]; then
    echo "  • Generating new Ed25519 host/client keypair..."
    ssh-keygen -t ed25519 -N "" -f "$KEY_FILE" -C "antigem-cloud-$CURRENT_USER" >/dev/null 2>&1
    chmod 600 "$KEY_FILE"
    chmod 644 "$KEY_FILE.pub"
fi

PUB_KEY="$(cat "$KEY_FILE.pub")"
if ! grep -qF "$PUB_KEY" "$SSH_DIR/authorized_keys" 2>/dev/null; then
    echo "$PUB_KEY" >> "$SSH_DIR/authorized_keys"
fi

# Set password for runner user so password authentication works if needed
SSH_PASS="${SSH_PASSWORD:-antigemcloud1}"
if command -v sudo >/dev/null 2>&1; then
    echo "$CURRENT_USER:$SSH_PASS" | sudo chpasswd 2>/dev/null || true
fi

# 4. Configure sshd daemon safely
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
CONFIG_FILE="$SSHD_CONFIG_DIR/99-antigem.conf"

CONFIG_CONTENT="Port $SSH_PORT
PubkeyAuthentication yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PermitRootLogin prohibit-password
AllowTcpForwarding yes
GatewayPorts yes
ClientAliveInterval 30
ClientAliveCountMax 10
PermitUserEnvironment yes
AuthorizedKeysFile .ssh/authorized_keys"

if command -v sudo >/dev/null 2>&1; then
    sudo mkdir -p "$SSHD_CONFIG_DIR"
    echo "$CONFIG_CONTENT" | sudo tee "$CONFIG_FILE" >/dev/null
    sudo chmod 644 "$CONFIG_FILE"
    # Ensure run directory exists
    sudo mkdir -p /run/sshd
    sudo chmod 755 /run/sshd
    # Restart or start ssh service
    sudo service ssh restart || sudo /usr/sbin/sshd
else
    mkdir -p "$SSHD_CONFIG_DIR"
    echo "$CONFIG_CONTENT" > "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
    mkdir -p /run/sshd
    chmod 755 /run/sshd
    service ssh restart || /usr/sbin/sshd
fi

# Verify sshd is running
if pgrep -x sshd >/dev/null || pgrep -f "/usr/sbin/sshd" >/dev/null; then
    echo "  ✅ OpenSSH server is running on port $SSH_PORT"
else
    echo "  ❌ Warning: sshd process was not detected!"
fi
echo "============================================================"
