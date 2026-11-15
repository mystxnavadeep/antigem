#!/usr/bin/env bash
# ==============================================================================
# antiGem Cloud Workspace - Google Drive Download Script
# Downloads the latest encrypted backup archive from Google Drive.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_PATH="${1:-${TMPDIR:-/tmp}/latest_backup.tar.gz.enc}"

if [ -z "${GDRIVE_CREDENTIALS_JSON:-}" ]; then
    echo "ℹ GDRIVE_CREDENTIALS_JSON is not configured. Clean startup without previous cloud restore."
    exit 0
fi

echo "============================================================"
echo "  ⚡ antiGem Cloud: Downloading Latest Backup from Google Drive"
echo "============================================================"
echo "  • Destination: $OUTPUT_PATH"

mkdir -p "$(dirname "$OUTPUT_PATH")"

if python3 "$SCRIPT_DIR/gdrive_helper.py" download-latest "$OUTPUT_PATH"; then
    echo "  ✅ Latest backup downloaded successfully."
    # Attempt to download checksum if available
    python3 "$SCRIPT_DIR/gdrive_helper.py" download-latest "${OUTPUT_PATH}.sha256" --pattern "$(basename "$OUTPUT_PATH").sha256" 2>/dev/null || true
else
    echo "  ℹ No previous backup was downloaded (fresh environment)."
fi
echo "============================================================"
