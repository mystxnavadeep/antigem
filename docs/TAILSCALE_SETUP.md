# antiGem Cloud Workspace: Tailscale Setup Guide

This guide details how to configure secure, private zero-trust networking between your Android phone running the antiGem APK and the ephemeral GitHub Actions cloud runner.

---

## 1. Authentication Principle: Auth Key ONLY

antiGem Cloud uses a dedicated **Tailscale Auth Key** (`TAILSCALE_AUTH_KEY`).
- **NO Tailscale OAuth Client ID is required.**
- **NO Tailscale OAuth Client Secret is required.**
- The auth key allows the ephemeral GitHub runner to authenticate directly into your Tailnet and obtain a private 100.x.y.z IP address without opening any ports to the public internet.

---

## 2. Generating the Tailscale Auth Key

1. Log into your [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys).
2. Go to **Settings -> Keys**.
3. Under **Auth keys**, click **Generate auth key...**.
4. Configure key settings:
   - **Description**: `antiGem Cloud Runner`
   - **Reusable**: Checked (allows multiple workflow runs over time with the same key)
   - **Expiration**: Select your preferred expiry (e.g. 90 days or custom)
   - **Ephemeral**: Checked (Recommended: automatically removes runner nodes from your device list once the runner terminates)
   - **Pre-authorized**: Checked (connects immediately without manual approval in admin console)
   - **Tags** (Optional): If your tailnet requires tags, add a tag such as `tag:server`
5. Click **Generate key**.
6. Copy the generated key (format: `tskey-auth-k...`).
7. In your GitHub repository:
   - Go to **Settings -> Secrets and variables -> Actions**.
   - Click **New repository secret**.
   - Name: `TAILSCALE_AUTH_KEY`
   - Secret: Paste the `tskey-auth-k...` value.

---

## 3. Recommended Tailscale ACL Configuration

If you use Tailscale Access Control Lists (ACLs), ensure your phone and runner can communicate on the required ports (1234, 1235, 22).

Example ACL configuration in `Access Controls`:

```jsonc
{
  "tagOwners": {
    "tag:server": ["autogroup:admin"]
  },
  "acls": [
    // Allow devices in your tailnet to reach antiGem services on tagged runners
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": [
        "tag:server:22",    // SSH
        "tag:server:1234",  // antiGem IDE Bridge
        "tag:server:1235"   // AGY Hub RPC
      ]
    }
  ]
}
```

If you do not use tag-based enforcement, Tailscale's default policy allows full communication between devices owned by the same user account.

---

## 4. How antiGem Connects

During the workflow, `scripts/setup-tailscale.sh` executes:
```bash
tailscale up --authkey="${TAILSCALE_AUTH_KEY}" --hostname=antigem-cloud-runner --accept-routes --ephemeral=true
```

1. Tailscale assigns a 100.x.y.z IPv4 address to the runner.
2. The script extracts only this private IPv4 address (`tailscale ip -4`).
3. The IPv4 address is presented in the GitHub Actions summary and workflow log.
4. The private endpoints are accessible ONLY from devices signed into your Tailnet (such as your Android phone).
