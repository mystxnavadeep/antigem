# antiGem Android APK: Cloud Workspace Connectivity Guide

The existing antiGem Android APK connects natively to remote cloud runners without requiring any APK modifications.

---

## 1. Supported Ports & Services

| Service | Port | Protocol | Purpose in antiGem |
|---|---|---|---|
| **antiGem Go IDE Bridge** | `1234` | HTTP / WebSocket | File explorer, project creation, Git operations, terminal relay, custom plugins API |
| **AGY Hub Supervisor** | `1235` | HTTP / RPC | Antigravity CLI Language Server, prompt dispatch, token management, agent sessions |
| **OpenSSH Server** | `22` | SSH | Remote tmux session control, process health, reverse port forwards for phone MCP tools |

---

## 2. In-App Configuration Steps

1. On your Android phone, ensure the **Tailscale app** is connected to your Tailnet.
2. Open the **antiGem APK**.
3. Tap **Settings** (gear icon) in the bottom navigation bar.
4. Select **Servers & Connectivity**.
5. Switch the mode from **Local** to **Remote**.
6. Fill in the connection parameters obtained from your GitHub Actions run:

| Field in Settings | Value to Enter | Notes |
|---|---|---|
| **IDE Bridge address** | `http://<RUNNER_TAILSCALE_IP>:1234` | Replace with runner IP (e.g. `http://100.115.92.14:1234`) |
| **AGY Hub address** | `http://<RUNNER_TAILSCALE_IP>:1235` | Replace with runner IP (e.g. `http://100.115.92.14:1235`) |
| **SSH host** | `<RUNNER_TAILSCALE_IP>` | The runner Tailscale IP |
| **SSH port** | `22` | Standard OpenSSH port |
| **SSH username** | `runner` | The user account on GitHub Actions runner |
| **SSH private key** | *(Generated key or empty)* | Leave empty if passwordless or paste `antigem_ed25519` key |
| **Security token** | `12-character token` | Copied from GitHub Actions step summary |
| **Proxy access header** | *(Leave blank)* | Direct Tailscale does not require reverse proxy headers |

7. Tap **Test Hub** -> Should show `answered HTTP 200` or `active`.
8. Tap **Test Bridge** -> Should show `linux/amd64` and green status.
9. Tap **Test SSH** -> Should show `Linux ... runner ... tmux: yes`.
10. Tap **Save Settings**.

---

## 3. Runner Restart & IP Update Procedure

Because GitHub Actions runners are created on-demand, each new workflow execution is assigned a new Tailscale IP address:

1. When a runner starts, open the workflow run in GitHub Actions.
2. Check the **Display Connection Info for Android APK** step summary.
3. Note the new **Tailscale IP** address.
4. Open antiGem on your phone:
   - Navigate to **Settings -> Servers & Connectivity**.
   - Update the IP address in **IDE Bridge address**, **AGY Hub address**, and **SSH host**.
   - Tap **Save Settings**.
5. Your workspace projects, chat histories, and state will automatically have been restored from your Google Drive backup!
