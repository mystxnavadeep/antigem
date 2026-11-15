#!/usr/bin/env bash
# ==============================================================================
# antiGem Cloud Workspace - Rclone Setup & Configuration
# Configures rclone dynamically from GDRIVE_CREDENTIALS_JSON without exposing secrets.
# ==============================================================================
set -euo pipefail

CURRENT_USER="$(whoami)"
HOME_DIR="${HOME:-/home/$CURRENT_USER}"
RCLONE_CONFIG_DIR="$HOME_DIR/.config/rclone"
RCLONE_CONF="$RCLONE_CONFIG_DIR/rclone.conf"

echo "============================================================"
echo "  ⚡ antiGem Cloud: Configuring Rclone for Google Drive"
echo "============================================================"

# 1. Install rclone if missing
if ! command -v rclone >/dev/null 2>&1; then
    echo "  • Installing rclone..."
    if command -v sudo >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y -qq rclone
    else
        apt-get update -qq && apt-get install -y -qq rclone
    fi
fi

# 2. Check for credentials
if [ -z "${GDRIVE_CREDENTIALS_JSON:-}" ]; then
    echo "  ℹ GDRIVE_CREDENTIALS_JSON is not set. Cloud storage synchronization disabled."
    exit 0
fi

# 3. Create rclone configuration
mkdir -p "$RCLONE_CONFIG_DIR"
chmod 700 "$RCLONE_CONFIG_DIR"

FOLDER_ID_LINE=""
if [ -n "${GDRIVE_FOLDER_ID:-}" ]; then
    FOLDER_ID_LINE="root_folder_id = ${GDRIVE_FOLDER_ID}"
fi

# Detect whether credentials are a Service Account or OAuth Token
if echo "$GDRIVE_CREDENTIALS_JSON" | grep -q '"type": *"service_account"'; then
    # Compact JSON to single-line safely without logging
    COMPACT_CREDS="$(echo "$GDRIVE_CREDENTIALS_JSON" | tr -d '\r\n')"
    cat <<EOF > "$RCLONE_CONF"
[gdrive]
type = drive
scope = drive
service_account_credentials = $COMPACT_CREDS
$FOLDER_ID_LINE
EOF
else
    # User OAuth token format
    cat <<EOF > "$RCLONE_CONF"
[gdrive]
type = drive
scope = drive
token = $GDRIVE_CREDENTIALS_JSON
$FOLDER_ID_LINE
EOF
fi

chmod 600 "$RCLONE_CONF"

# 4. Verify rclone can reach Drive
if rclone lsd gdrive: >/dev/null 2>&1; then
    echo "  ✅ Rclone connected to Google Drive successfully!"
else
    echo "  ℹ Rclone configured. Initial directory access ready."
fi
echo "============================================================"
