#!/usr/bin/env bash
# ==============================================================================
# antiGem Cloud Workspace - Backup Integrity Verifier
# Verifies checksums, decryption, and archive integrity without exposing keys.
# ==============================================================================
set -euo pipefail

ARCHIVE_PATH="${1:-}"

if [ -z "$ARCHIVE_PATH" ]; then
    echo "❌ Error: No archive specified for verification."
    echo "Usage: $0 <path_to_encrypted_archive>"
    exit 1
fi

if [ ! -f "$ARCHIVE_PATH" ]; then
    echo "❌ Error: Archive not found at '$ARCHIVE_PATH'"
    exit 1
fi

echo "============================================================"
echo "  ⚡ antiGem Cloud: Verifying Backup Archive"
echo "============================================================"
echo "  • Archive: $(basename "$ARCHIVE_PATH")"
echo "  • Size:    $(du -h "$ARCHIVE_PATH" | cut -f1)"

# 1. Check SHA256 if available
if [ -f "${ARCHIVE_PATH}.sha256" ]; then
    echo "  • Checking SHA-256 checksum..."
    (cd "$(dirname "$ARCHIVE_PATH")" && sha256sum -c "$(basename "${ARCHIVE_PATH}.sha256")" >/dev/null 2>&1)
    if [ $? -eq 0 ]; then
        echo "    ✔ SHA-256 Checksum verified."
    else
        echo "    ❌ SHA-256 Checksum MISMATCH or corrupted!"
        exit 1
    fi
fi

# 2. Verify Decryption & Tar Structure
if [ -n "${BACKUP_ENCRYPTION_KEY:-}" ]; then
    echo "  • Testing decryption and tar integrity..."
    if command -v openssl >/dev/null 2>&1; then
        if openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -in "$ARCHIVE_PATH" -pass env:BACKUP_ENCRYPTION_KEY 2>/dev/null | tar -tz >/dev/null 2>&1; then
            echo "    ✔ Archive decrypts cleanly via OpenSSL and tar structure is intact."
        else
            echo "    ❌ OpenSSL decryption failed! Invalid key or corrupted archive."
            exit 1
        fi
    elif command -v gpg >/dev/null 2>&1; then
        if echo "$BACKUP_ENCRYPTION_KEY" | gpg --batch --yes --passphrase-fd 0 -d "$ARCHIVE_PATH" 2>/dev/null | tar -tz >/dev/null 2>&1; then
            echo "    ✔ Archive decrypts cleanly via GPG and tar structure is intact."
        else
            echo "    ❌ GPG decryption failed! Invalid key or corrupted archive."
            exit 1
        fi
    else
        echo "    ❌ Error: Neither openssl nor gpg found to verify encrypted archive."
        exit 1
    fi
else
    # If not encrypted, check plain tar
    if tar -tzf "$ARCHIVE_PATH" >/dev/null 2>&1; then
        echo "    ✔ Plain archive structure verified."
    else
        echo "    ❌ Archive verification failed! (Missing BACKUP_ENCRYPTION_KEY or invalid archive)"
        exit 1
    fi
fi

echo "  ✅ Backup integrity verified 100% successfully!"
echo "============================================================"
