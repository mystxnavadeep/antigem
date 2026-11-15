#!/usr/bin/env bash
# ==============================================================================
# antiGem Cloud Workspace - Encrypted Backup Packager
# Packages workspace, sessions, configs, MCP, skills, and auth state into an encrypted archive.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BACKUP_MODE="${1:-full}"   # "full" or "inc" (incremental)
DO_UPLOAD="${2:-upload}"   # "upload" or "local"

CURRENT_USER="$(whoami)"
HOME_DIR="${HOME:-/home/$CURRENT_USER}"
TMP_ROOT="${TMPDIR:-/tmp}"
TMP_DIR="${TMP_ROOT}/antigem_backup_$$"
TIMESTAMP="$(date +"%Y-%m-%d-%H-%M-%S")"
BACKUP_NAME="antigem_${BACKUP_MODE}_${TIMESTAMP}"
RAW_TAR="$TMP_DIR/${BACKUP_NAME}.tar.gz"
ENC_ARCHIVE="${TMP_ROOT}/${BACKUP_NAME}.tar.gz.enc"
SNAPSHOT_MARKER="$HOME_DIR/.antigem_last_backup_marker"

mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "============================================================"
echo "  ⚡ antiGem Cloud: Packaging Workspace ($BACKUP_MODE)"
echo "============================================================"
echo "  • Mode:      $BACKUP_MODE"
echo "  • Timestamp: $TIMESTAMP"
echo "  • Home:      $HOME_DIR"

# 1. Prepare Manifest
MANIFEST_FILE="$TMP_DIR/manifest.json"
cat <<EOF > "$MANIFEST_FILE"
{
  "project": "antiGem-Cloud",
  "version": "1.0.0",
  "backup_mode": "$BACKUP_MODE",
  "timestamp": "$TIMESTAMP",
  "user": "$CURRENT_USER",
  "host": "$(hostname 2>/dev/null || echo runner)"
}
EOF

# 2. Assemble Include Targets (Only existing paths)
INCLUDES=()
add_if_exists() {
    local target="$1"
    if [ -e "$HOME_DIR/$target" ]; then
        INCLUDES+=("$target")
    fi
}

cd "$HOME_DIR"

add_if_exists "projects"
add_if_exists ".gemini"
add_if_exists ".antigem"
add_if_exists ".antigem_bridge"
add_if_exists ".claude"
add_if_exists ".claude.json"
add_if_exists ".opencode"
add_if_exists ".codex"
add_if_exists ".ssh"
add_if_exists "extensions"
add_if_exists "logs"
add_if_exists ".bashrc"
add_if_exists ".profile"
add_if_exists ".gitconfig"

# Copy manifest into temp staging inside home
cp "$MANIFEST_FILE" "$HOME_DIR/.antigem_manifest.json"
INCLUDES+=(".antigem_manifest.json")

# 3. Define Exclusions (unnecessary caches, sockets, heavy modules)
EXCLUDES=(
    "--exclude=*.sock"
    "--exclude=*/cache/*"
    "--exclude=*/.cache/*"
    "--exclude=*/crashes/*"
    "--exclude=*/implicit/*"
    "--exclude=*/node_modules/*"
    "--exclude=*/.git/objects/*"
    "--exclude=*/.gemini/bin/*"
    "--exclude=*/.antigravity/bin/*"
    "--exclude=*.tmp"
)

# 4. Create Tarball (Full or Incremental)
echo "  • Archiving selected workspace items..."
TAR_CMD=(tar -czf "$RAW_TAR" "${EXCLUDES[@]}")

if [ "$BACKUP_MODE" = "inc" ] && [ -f "$SNAPSHOT_MARKER" ]; then
    echo "    (Incremental filter: files newer than last snapshot)"
    TAR_CMD+=(--newer-mtime="$SNAPSHOT_MARKER")
fi

# Run tar safely
"${TAR_CMD[@]}" "${INCLUDES[@]}" 2>/dev/null || true

# Update snapshot marker
touch "$SNAPSHOT_MARKER"
rm -f "$HOME_DIR/.antigem_manifest.json"

if [ ! -f "$RAW_TAR" ] || [ ! -s "$RAW_TAR" ]; then
    echo "❌ Error: Failed to create tar archive or archive is empty."
    exit 1
fi

RAW_SIZE="$(du -h "$RAW_TAR" | cut -f1)"
echo "    ✔ Archive size (unencrypted): $RAW_SIZE"

# 5. Encrypt Archive
if [ -n "${BACKUP_ENCRYPTION_KEY:-}" ]; then
    if command -v openssl >/dev/null 2>&1; then
        echo "  • Encrypting archive with AES-256-CBC (PBKDF2)..."
        openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
            -in "$RAW_TAR" \
            -out "$ENC_ARCHIVE" \
            -pass env:BACKUP_ENCRYPTION_KEY
        rm -f "$RAW_TAR"
    elif command -v gpg >/dev/null 2>&1; then
        echo "  • Encrypting archive with GPG symmetric AES256..."
        echo "$BACKUP_ENCRYPTION_KEY" | gpg --batch --yes --passphrase-fd 0 -c --cipher-algo AES256 -o "$ENC_ARCHIVE" "$RAW_TAR"
        rm -f "$RAW_TAR"
    else
        echo "  ❌ Error: Neither openssl nor gpg command found for backup encryption."
        exit 1
    fi
else
    echo "  ⚠️ Warning: BACKUP_ENCRYPTION_KEY not set. Archive will be unencrypted."
    ENC_ARCHIVE="${TMP_ROOT}/${BACKUP_NAME}.tar.gz"
    mv "$RAW_TAR" "$ENC_ARCHIVE"
fi

# 6. Generate SHA-256 Checksum
(cd "$(dirname "$ENC_ARCHIVE")" && sha256sum "$(basename "$ENC_ARCHIVE")" > "$(basename "$ENC_ARCHIVE").sha256")
echo "  ✔ SHA-256 Checksum generated: $(cat "${ENC_ARCHIVE}.sha256" | cut -d' ' -f1 | cut -c1-16)..."

# 7. Verify Backup before upload
echo "  • Running self-verification test..."
"$SCRIPT_DIR/verify-backup.sh" "$ENC_ARCHIVE"

# 8. Upload to Google Drive
if [ "$DO_UPLOAD" = "upload" ]; then
    "$SCRIPT_DIR/drive-upload.sh" "$ENC_ARCHIVE"
fi

echo "  ✅ Backup process finished successfully: $(basename "$ENC_ARCHIVE")"
echo "============================================================"
