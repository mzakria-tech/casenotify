# SF Notification Center

Salesforce case monitor for Red Hat OpenShift Support engineers.  
Polls your open cases via Red Hat GraphQL (supportshell), emails on status/comment changes.

No Chrome scraping, no Mail.app, no local web dashboard.

## Features

- **GraphQL case tracking** — open cases via supportshell OIDC (`yank --init`)
- **Email alerts** — supportshell → `smtp.corp.redhat.com`
- **macOS banners** — desktop notification on changes
- **LaunchAgent** — runs in the background every ~60s

## Prerequisites

- **macOS** (LaunchAgents) or Linux (systemd user)
- **Red Hat VPN**
- **Python 3**
- **SSH** to supportshell + OIDC (`yank --init`, auto-opened in Chrome on install)

## Fresh computer

```bash
# VPN on
cd ~/Desktop
git clone https://github.com/mzakria-tech/sf-notification-center.git
cd sf-notification-center
chmod +x install.sh update.sh start.sh stop.sh
./install.sh
```

`./install.sh` sets up SSH (password once if needed), runs `yank --init` (opens Chrome for SSO), and starts the poller.

## Update / heal

```bash
cd ~/Desktop/sf-notification-center
./update.sh
```

## Commands

| Command | Description |
|---------|-------------|
| `./install.sh` | Install poller + LaunchAgent |
| `./update.sh` | Pull, sync, yank token if needed, verify |
| `./start.sh` | Sync binaries + start poller |
| `./stop.sh` | Stop poller (also removes legacy dashboard) |
| `./install.sh uninstall` | Remove everything |
| `sf-case-poller status` | Status |
| `sf-case-poller --test-email` | Send a test email |
| `sf-case-poller health` | Health check |

## Configuration

Edit `~/.local/state/sf-poller-config.json`:

```json
{
  "notify_email": "you@redhat.com",
  "supportshell_user": "your-rh-username"
}
```

Optional: `SF_POLL_INTERVAL` (seconds, default via LaunchAgent is 60).

## Architecture

```
GraphQL (vpn.graphql.redhat.com via supportshell SSH)
        → sf-case-poller
        → supportshell SMTP → your inbox
        → macOS banner
```

## File locations

| File | Path |
|------|------|
| Poller | `~/.local/bin/sf-case-poller` |
| Config | `~/.local/state/sf-poller-config.json` |
| State / DB | `~/.local/state/sf-notification-center.db` |
| Log | `~/Library/Logs/sf-case-poller.log` |
| LaunchAgent | `~/Library/LaunchAgents/com.$USER.sf-case-poller.plist` |

## Author

Red Hat OpenShift Support
