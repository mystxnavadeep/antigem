#!/usr/bin/env bash
# ==============================================================================
# antiGem Cloud Workspace - Google Drive Download Script (via Rclone)
# Downloads the latest encrypted backup archive from Google Drive using rclone.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_PATH="${1:-${TMPDIR:-/tmp}/latest_backup.tar.gz.enc}"

if [ -z "${GDRIVE_CREDENTIALS_JSON:-}" ]; then
    echo "ℹ GDRIVE_CREDENTIALS_JSON is not configured. Clean startup without previous cloud restore."
    exit 0
fi

# Ensure rclone configuration is active
"$SCRIPT_DIR/setup-rclone.sh"

DEST_FOLDER="AntiGem-Cloud-Backups"

echo "============================================================"
echo "  ⚡ antiGem Cloud: Downloading Latest Backup via Rclone"
echo "============================================================"
echo "  • Destination: $OUTPUT_PATH"

mkdir -p "$(dirname "$OUTPUT_PATH")"

# Find latest backup matching antigem_*.enc
LATEST_FILE="$(rclone lsf "gdrive:$DEST_FOLDER" --include "antigem_*.enc" 2>/dev/null | sort -r | head -n 1 || true)"

if [ -n "$LATEST_FILE" ]; then
    echo "  • Found latest cloud backup: $LATEST_FILE"
    DOWNLOAD_DIR="$(dirname "$OUTPUT_PATH")"
    
    rclone copy "gdrive:$DEST_FOLDER/$LATEST_FILE" "$DOWNLOAD_DIR" --transfers 4 --retries 3
    if [ -f "$DOWNLOAD_DIR/$LATEST_FILE" ]; then
        mv -f "$DOWNLOAD_DIR/$LATEST_FILE" "$OUTPUT_PATH"
        echo "  ✔ Downloaded archive successfully."
    fi

    # Attempt to download checksum file as well
    rclone copy "gdrive:$DEST_FOLDER/${LATEST_FILE}.sha256" "$DOWNLOAD_DIR" 2>/dev/null || true
    if [ -f "$DOWNLOAD_DIR/${LATEST_FILE}.sha256" ]; then
        mv -f "$DOWNLOAD_DIR/${LATEST_FILE}.sha256" "${OUTPUT_PATH}.sha256"
        echo "  ✔ Downloaded SHA-256 checksum."
    fi
    echo "  ✅ Rclone restore download complete."
else
    echo "  ℹ No previous backup found in 'gdrive:$DEST_FOLDER' (fresh environment)."
fi
echo "============================================================"
