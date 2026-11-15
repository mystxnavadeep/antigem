# antiGem Cloud Workspace: Troubleshooting Guide

This guide covers common issues and resolutions when running antiGem Cloud with GitHub Actions, Tailscale, and Google Drive.

---

## 1. Tailscale Issues

### "Tailscale connection failed or timed out"
- **Cause**: The `TAILSCALE_AUTH_KEY` secret is invalid, expired, or revoked.
- **Solution**:
  1. Generate a new pre-authorized, reusable key in [Tailscale Admin Settings -> Keys](https://login.tailscale.com/admin/settings/keys).
  2. Update the `TAILSCALE_AUTH_KEY` secret in your GitHub repository.

### "Phone cannot reach the runner Tailscale IP"
- **Cause**:
  1. Your phone is not connected to the Tailscale VPN app.
  2. Tailscale ACLs are blocking traffic between the phone and the runner.
- **Solution**:
  1. Open the Tailscale app on Android and ensure it says "Connected".
  2. Ping the runner Tailscale IP from Termux: `ping 100.x.y.z`.
  3. Verify your Tailnet ACL policy allows ports 22, 1234, and 1235.

---

## 2. Google Drive Backup & Restore Issues

### "GDRIVE_CREDENTIALS_JSON secret is not set"
- **Cause**: The workflow did not find Google Drive credentials, so it ran in clean/ephemeral mode.
- **Solution**: Paste your Service Account JSON key into GitHub Repository Secrets under `GDRIVE_CREDENTIALS_JSON`.

### "Google Drive 404 / 403 Forbidden on upload"
- **Cause**: The service account does not have edit access to the backup folder.
- **Solution**:
  1. Find the email address in `client_email` within your credentials JSON (e.g., `antigem-backup@project.iam.gserviceaccount.com`).
  2. In Google Drive, share your backup folder (`AntiGem-Cloud-Backups`) with that email address with **Editor** access.

### "Decryption failed! Invalid key or corrupted archive"
- **Cause**: The `BACKUP_ENCRYPTION_KEY` in GitHub Secrets does not match the key that encrypted the existing backup.
- **Solution**: Ensure consistent use of the same `BACKUP_ENCRYPTION_KEY` across all workflow runs.

---

## 3. Server & APK Connectivity Issues

### "HTTP 401 Unauthorized / Token Rejected"
- **Cause**: The security token entered in the Android app differs from the token generated on the server.
- **Solution**:
  1. Check the GitHub Actions step summary: **Display Connection Info for Android APK**.
  2. Copy the exact 12-character **Security Token** into the antiGem Android app under **Settings -> Servers & Connectivity -> Security token**.
  3. Save settings.

### "Connection Refused on Port 1234 or 1235"
- **Cause**: The bridge or hub process stopped or is still starting up.
- **Solution**:
  1. Check the workflow logs under **Start AntiGem Services**.
  2. Ensure Go 1.23 compiled `bin/agy_ide_bridge` without errors.
  3. Verify `bridge.log` in the workflow output for any agent binary path issues.

---

## 4. Runner Lifespan & Persistence Limitations

- **GitHub Actions 6-Hour Limit**: GitHub automatically kills any job running longer than 6 hours.
- **Scheduled 5h50m Shutdown**: antiGem Cloud runs a timer that initiates a full backup and clean shutdown at 5 hours 50 minutes (350 minutes) so your data is safely backed up before any hard cutoff.
- **Restarting the Cloud Workspace**:
  1. Go to your repository on GitHub.
  2. Click **Actions -> AntiGem Cloud Workspace -> Run workflow**.
  3. The new runner will automatically pull your latest backup from Google Drive, restore all projects and sessions, and assign a new Tailscale IP.
  4. Update the IP in your Android app to resume working seamlessly!
