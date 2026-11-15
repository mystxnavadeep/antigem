#!/usr/bin/env bash
# ==============================================================================
# antiGem Cloud Workspace - Google Drive Upload Script
# Uploads encrypted backup archives to Google Drive securely.
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

echo "============================================================"
echo "  ⚡ antiGem Cloud: Uploading Backup to Google Drive"
echo "============================================================"
echo "  • Archive: $(basename "$ARCHIVE_PATH")"
echo "  • Size:    $(du -h "$ARCHIVE_PATH" | cut -f1)"

# Execute upload via python helper
python3 "$SCRIPT_DIR/gdrive_helper.py" upload "$ARCHIVE_PATH"

# Also upload SHA256 checksum if exists
if [ -f "${ARCHIVE_PATH}.sha256" ]; then
    python3 "$SCRIPT_DIR/gdrive_helper.py" upload "${ARCHIVE_PATH}.sha256"
fi

# Prune old backups, keeping recent 15
python3 "$SCRIPT_DIR/gdrive_helper.py" cleanup --keep 15 2>/dev/null || true

echo "  ✅ Backup upload and retention check complete."
echo "============================================================"
