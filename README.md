# casenotify

Salesforce case monitor for Red Hat OpenShift Support engineers.  
Polls open cases via **Red Hat GraphQL** (supportshell), emails via **supportshell SMTP**, and shows a live dashboard at **http://localhost:8090**.

No Chrome scraping. No Mail.app.

**Full tech stack, architecture, auth, files, and ops:** → **[TECH.md](TECH.md)**

## Quick start

```bash
# VPN on
cd ~/Desktop
git clone https://github.com/mzakria-tech/casenotify.git
cd casenotify
./install.sh          # SSH + yank --init (Chrome SSO) + start + open dashboard
```

Already installed:

```bash
cd ~/Desktop/casenotify
git pull && ./start.sh    # opens http://localhost:8090
# or
./update.sh               # pull + heal + verify + open dashboard
```

## Commands

| Command | Description |
|---------|-------------|
| `./install.sh` | First-time install |
| `./update.sh` | Pull, sync, yank if needed, verify |
| `./start.sh` | Start services + open dashboard |
| `./stop.sh` | Stop services |
| `sf-case-poller status` / `health` / `test-email` | Ops checks |

## Author

Red Hat OpenShift Support
