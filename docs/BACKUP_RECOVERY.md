# antiGem Cloud Workspace: Backup & Recovery Guide

This document describes the automated, encrypted backup and restore system for antiGem Cloud running on GitHub Actions runners.

---

## 1. Overview & Architecture

GitHub Actions runners are ephemeral: any runner machine is destroyed after the workflow finishes or hits its time limit (maximum 6 hours).

To provide persistent and recoverable workspace state, antiGem Cloud implements a multi-tier lifecycle:
1. **Startup Restore**: The runner queries Google Drive for the latest encrypted backup archive, verifies its SHA-256 checksum and AES-256 decryption integrity, and extracts workspace data before launching antiGem services.
2. **5-Minute Incremental Backup**: Every 5 minutes during workflow execution, newly modified files across projects and sessions are packaged into an encrypted delta archive and uploaded to Google Drive.
3. **30-Minute Full Backup**: Every 30 minutes, a comprehensive full archive is generated and synchronized to Google Drive.
4. **5h50m Final Backup**: Prior to the 6-hour runner limit, at 5 hours 50 minutes (350m), the runner stops new operations, executes a final verified full backup, and completes cleanly.

---

## 2. Backup Content & Scope

The following directories and state files are included in the backup:

| Path | Description |
|---|---|
| `~/projects/` | User code repositories, workspaces, and project directories |
| `~/.gemini/` | Antigravity CLI session histories (`brain/`), conversation database (`conversation_summaries.db`), MCP and skills |
| `~/.antigem_bridge/` | Persistent 12-character bridge security token (`csrf_token.txt`) |
| `~/.antigem/` | Browser extension runtime data, upload buffers, and plugin storage |
| `~/.claude/`, `~/.claude.json` | Claude Code CLI sessions, configuration, and state |
| `~/.opencode/` | OpenCode CLI sessions and models configuration |
| `~/.codex/` | OpenAI Codex CLI configuration and session state |
| `~/.ssh/` | SSH server authorization (`authorized_keys`) and persistent client keys |
| `~/extensions/` | Bundled and custom antiGem plugins |
| `~/logs/` | Server and extension host run logs |
| `~/.bashrc`, `~/.profile` | Terminal environment configurations |

### Excluded Items (To save bandwidth and avoid corrupted locks)
- Unix domain sockets (`*.sock`)
- Heavy cache folders (`*/cache/*`, `*/.cache/*`)
- Temporary crash dumps (`*/crashes/*`)
- Node dependency directories (`*/node_modules/*`)
- Git pack files in dependencies (`*/.git/objects/*`)
- Temporary runtime files (`*.tmp`)

---

## 3. Security & Encryption

- **Encryption Standard**: AES-256-CBC with PBKDF2 key derivation and 100,000 iterations via OpenSSL:
  ```bash
  openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -in "$ARCHIVE" -out "$ARCHIVE.enc" -pass env:BACKUP_ENCRYPTION_KEY
  ```
- **Integrity Verification**: SHA-256 checksums are calculated immediately upon archive generation and uploaded alongside the archive. Prior to restoration, the checksum and archive decodability are validated:
  ```bash
  ./scripts/verify-backup.sh "$ARCHIVE.enc"
  ```
- **No Plaintext Leaks**: Encryption keys and Google Drive credentials are read strictly from environment variables and GitHub Secrets (`BACKUP_ENCRYPTION_KEY`, `GDRIVE_CREDENTIALS_JSON`). They are never printed to terminal or workflow logs.

---

## 4. Google Drive Service Account Configuration

To enable automated Google Drive sync:

1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Create or select a Google Cloud project.
3. Enable the **Google Drive API** under **APIs & Services -> Library**.
4. Navigate to **IAM & Admin -> Service Accounts** and click **Create Service Account**.
5. Give the account a name (e.g., `antigem-backup-bot`) and click **Create and Continue**.
6. Click on the created service account, go to the **Keys** tab, click **Add Key -> Create new key**, and choose **JSON**.
7. Download the JSON key file.
8. In your personal Google Drive, create a folder named `AntiGem-Cloud-Backups`.
9. Share this folder with the service account's email address (e.g. `antigem-backup-bot@your-project.iam.gserviceaccount.com`) with **Editor** permissions.
10. Copy the entire contents of the downloaded JSON file and paste it into GitHub Repository Secrets as:
    `GDRIVE_CREDENTIALS_JSON`

---

## 5. Manual Backup & Restore Procedures

### Triggering Manual Backup locally or on runner
```bash
# Full backup and upload
./scripts/backup.sh full upload

# Incremental backup only
./scripts/backup.sh inc upload

# Local backup without cloud upload
./scripts/backup.sh full local
```

### Manually Restoring an Archive
```bash
export BACKUP_ENCRYPTION_KEY="your-encryption-passphrase"
./scripts/restore.sh /path/to/backup.tar.gz.enc
```
