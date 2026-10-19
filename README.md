# SF Notification Center

Salesforce case status monitor for Red Hat OpenShift Support engineers.  
Polls your Salesforce case list view every 5 minutes, sends email alerts on status changes, and shows a live web dashboard.

![Dashboard](https://img.shields.io/badge/Dashboard-localhost:8090-blue) ![macOS](https://img.shields.io/badge/macOS-only-lightgrey)

## Features

- **Real-time case tracking** — Monitors your Salesforce cases via Chrome browser automation
- **Email alerts** — Sends to your email via Mail.app when a case status changes
- **macOS notifications** — Desktop banners on status changes
- **Web dashboard** — Colorful live dashboard at `http://localhost:8090`
  - Service health (Chrome, Mail.app, Poller, Mail Server)
  - One-click start buttons for stopped services
  - Tracked cases table with status, severity, owner, contact
  - Email notification log
  - Activity log
  - Settings panel to change the monitored list view URL

## Prerequisites

- **macOS** (uses LaunchAgents, AppleScript, Mail.app)
- **Google Chrome** — logged into Red Hat Salesforce (`redhatsupport.lightning.force.com`)
- **Chrome setting**: View → Developer → Allow JavaScript from Apple Events ✓
- **Mail.app** — configured with your email account
- **Python 3** with `aiosmtpd` (`pip3 install aiosmtpd`)

## Quick Start

```bash
# Install (first time — VPN on; may ask RH password once for SSH)
chmod +x install.sh start.sh stop.sh uninstall.sh update.sh
./install.sh

# Start all services
./start.sh

# Open dashboard
open http://localhost:8090
```

## Update / heal (any laptop after git pull)

GraphQL 400 / `DISCOVERY_FAILED` / stale heartbeat — one command from the repo:

```bash
cd ~/Desktop/sf-notification-center   # or your clone path
./update.sh
```

That runs: `git pull` → sync `~/.local/bin` → restart LaunchAgents → `sf-case-poller --once`.  
Same command is printed in the poller log and dashboard Activity Log when discovery fails.

## Commands

| Command | Description |
|---------|-------------|
| `./install.sh` | Install scripts, dependencies, and LaunchAgents |
| `./update.sh` | Pull latest, sync binaries, restart, verify GraphQL |
| `./start.sh` | Sync binaries from this repo + start services |
| `./stop.sh` | Stop all services |
| `./uninstall.sh` | Remove everything |

## Configuration

### Change monitored list view

**Option 1 — Dashboard**: Open `http://localhost:8090`, scroll to ⚙️ Monitor Settings, paste a new URL, click Save.

**Option 2 — Environment variable**:
```bash
export SF_CASE_LIST_URL="https://redhatsupport.lightning.force.com/lightning/o/Case/list?filterName=YourView"
```

**Option 3 — Config file** (`~/.local/state/sf-poller-config.json`):
```json
{ "case_list_url": "https://redhatsupport.lightning.force.com/lightning/o/Case/list?filterName=YourView" }
```

### Change poll interval

Set `SF_POLL_INTERVAL` in the LaunchAgent plist (default: 300 seconds = 5 min).

### Change notification email

Set during `./install.sh` or edit `~/.local/state/sf-poller-config.json`.

## Architecture

```
Chrome (Salesforce)  →  AppleScript JS  →  sf-case-poller  →  Mail.app (email)
                                                ↓                    ↓
                                         State JSON           local-mailserver
                                                                (SMTP + Web UI)
                                                              localhost:8090
```

## File Locations

| File | Path |
|------|------|
| Poller script | `~/.local/bin/sf-case-poller` |
| Dashboard script | `~/.local/bin/local-mailserver` |
| Case state | `~/.local/state/sf-case-status.json` |
| Config | `~/.local/state/sf-poller-config.json` |
| Poller log | `~/Library/Logs/sf-case-poller.log` |
| LaunchAgents | `~/Library/LaunchAgents/com.sf-notify.case-poller.plist` |

## Author

Red Hat OpenShift Support
