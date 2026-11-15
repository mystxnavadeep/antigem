#!/usr/bin/env bash
# ==============================================================================
# antiGem Cloud Workspace - Workspace & Session Restorer
# Restores projects, chat histories, configurations, and SSH keys from Google Drive.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_USER="$(whoami)"
HOME_DIR="${HOME:-/home/$CURRENT_USER}"
INPUT_ARCHIVE="${1:-}"

echo "============================================================"
echo "  ⚡ antiGem Cloud: Workspace Restore & Initialization"
echo "============================================================"
echo "  • User: $CURRENT_USER"
echo "  • Home: $HOME_DIR"

# 1. Download Latest Backup if not provided explicitly
ARCHIVE_TO_RESTORE="$INPUT_ARCHIVE"
if [ -z "$ARCHIVE_TO_RESTORE" ]; then
    DOWNLOAD_DEST="${TMPDIR:-/tmp}/latest_antigem_backup.tar.gz.enc"
    "$SCRIPT_DIR/drive-download.sh" "$DOWNLOAD_DEST"
    if [ -f "$DOWNLOAD_DEST" ]; then
        ARCHIVE_TO_RESTORE="$DOWNLOAD_DEST"
    fi
fi

# 2. Check if a backup archive was found
if [ -n "$ARCHIVE_TO_RESTORE" ] && [ -f "$ARCHIVE_TO_RESTORE" ]; then
    echo "  • Backup found: $(basename "$ARCHIVE_TO_RESTORE") ($(du -h "$ARCHIVE_TO_RESTORE" | cut -f1))"
    
    # Verify backup integrity before unpacking
    if "$SCRIPT_DIR/verify-backup.sh" "$ARCHIVE_TO_RESTORE"; then
        echo "  • Unpacking workspace archive into $HOME_DIR..."
        if [ -n "${BACKUP_ENCRYPTION_KEY:-}" ]; then
            if command -v openssl >/dev/null 2>&1; then
                openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
                    -in "$ARCHIVE_TO_RESTORE" \
                    -pass env:BACKUP_ENCRYPTION_KEY \
                    | tar -xz -C "$HOME_DIR"
            elif command -v gpg >/dev/null 2>&1; then
                echo "$BACKUP_ENCRYPTION_KEY" | gpg --batch --yes --passphrase-fd 0 -d "$ARCHIVE_TO_RESTORE" \
                    | tar -xz -C "$HOME_DIR"
            fi
        else
            tar -xzf "$ARCHIVE_TO_RESTORE" -C "$HOME_DIR"
        fi
        echo "  ✔ Archive extraction complete."
    else
        echo "  ❌ Warning: Backup verification failed. Proceeding with clean environment initialization."
    fi
else
    echo "  ℹ No previous backup found. Initializing clean cloud workspace."
fi

# 3. Ensure base directory structure exists
mkdir -p "$HOME_DIR/projects"
mkdir -p "$HOME_DIR/.gemini"
mkdir -p "$HOME_DIR/.antigem/uploads"
mkdir -p "$HOME_DIR/.antigem_bridge"
mkdir -p "$HOME_DIR/extensions"
mkdir -p "$HOME_DIR/logs"
mkdir -p "$HOME_DIR/.ssh"

# 4. Enforce strict permissions for SSH files if restored
chmod 700 "$HOME_DIR/.ssh"
if [ -f "$HOME_DIR/.ssh/authorized_keys" ]; then
    chmod 600 "$HOME_DIR/.ssh/authorized_keys"
fi
find "$HOME_DIR/.ssh" -type f -name "*_ed25519" -o -name "*_rsa" -o -name "id_*" -exec chmod 600 {} + 2>/dev/null || true

# 5. Restore or initialize CSRF security token
TOKEN_FILE="$HOME_DIR/.antigem_bridge/csrf_token.txt"
if [ ! -f "$TOKEN_FILE" ] || [ "$(wc -c < "$TOKEN_FILE" | tr -d ' ')" -lt 12 ]; then
    # Generate 12-character alphanumeric token
    NEW_TOKEN="$(tr -dc 'a-z0-9' < /dev/urandom | head -c 12 || echo 'n6mjyd8v6nzp')"
    echo "$NEW_TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    echo "  • Initialized new 12-char bridge security token: $NEW_TOKEN"
else
    EXISTING_TOKEN="$(cat "$TOKEN_FILE" | tr -d '[:space:]')"
    echo "  • Restored persistent security token: $EXISTING_TOKEN"
fi

echo "  ✅ Workspace restored and ready."
echo "============================================================"
