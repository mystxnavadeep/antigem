#!/usr/bin/env bash
# ==============================================================================
# antiGem Cloud Workspace - Google Drive Upload Script (via Rclone)
# Uploads encrypted backup archives to Google Drive securely using rclone.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_PATH="${1:-}"

if [ -z "$ARCHIVE_PATH" ]; then
    echo "❌ Error: No archive file specified for upload."
    echo "Usage: $0 <path_to_archive>"
    exit 1
fi

if [ ! -f "$ARCHIVE_PATH" ]; then
    echo "❌ Error: File not found at '$ARCHIVE_PATH'"
    exit 1
fi

if [ -z "${GDRIVE_CREDENTIALS_JSON:-}" ]; then
    echo "⚠️ Warning: GDRIVE_CREDENTIALS_JSON secret is not set. Google Drive upload skipped."
    exit 0
fi

# Ensure rclone configuration is active
"$SCRIPT_DIR/setup-rclone.sh"

DEST_FOLDER="AntiGem-Cloud-Backups"
FILE_NAME="$(basename "$ARCHIVE_PATH")"

echo "============================================================"
echo "  ⚡ antiGem Cloud: Uploading Backup via Rclone"
echo "============================================================"
echo "  • Archive:     $FILE_NAME"
echo "  • Size:        $(du -h "$ARCHIVE_PATH" | cut -f1)"
echo "  • Destination: gdrive:$DEST_FOLDER"

# Upload archive with high-speed multi-threaded transfer
rclone copy "$ARCHIVE_PATH" "gdrive:$DEST_FOLDER" \
    --drive-chunk-size 64M \
    --transfers 4 \
    --retries 3

# Upload checksum if present
if [ -f "${ARCHIVE_PATH}.sha256" ]; then
    rclone copy "${ARCHIVE_PATH}.sha256" "gdrive:$DEST_FOLDER" --retries 3
fi

# Retention Policy: Keep 15 most recent backups, prune older ones
ALL_BACKUPS=$(rclone lsf "gdrive:$DEST_FOLDER" --include "antigem_*.enc" 2>/dev/null | sort || true)
BACKUP_COUNT=$(echo "$ALL_BACKUPS" | grep -c "antigem_" || echo 0)

if [ "$BACKUP_COUNT" -gt 15 ]; then
    EXCESS=$((BACKUP_COUNT - 15))
    echo "  • Pruning $EXCESS old backup(s) from Google Drive..."
    OLD_BACKUPS=$(echo "$ALL_BACKUPS" | head -n "$EXCESS")
    for old_file in $OLD_BACKUPS; do
        if [ -n "$old_file" ]; then
            rclone delete "gdrive:$DEST_FOLDER/$old_file" 2>/dev/null || true
            rclone delete "gdrive:$DEST_FOLDER/${old_file}.sha256" 2>/dev/null || true
            echo "    Deleted: $old_file"
        fi
    done
fi

echo "  ✅ Rclone upload and retention management complete!"
echo "============================================================"
