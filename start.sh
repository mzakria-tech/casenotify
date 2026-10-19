#!/bin/bash
# Start all SF Notification Center services (self-heals LaunchAgents; no Mail.app)

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=sf-service-lib.sh
source "$REPO_DIR/sf-service-lib.sh"

echo "Starting SF Notification Center..."
echo "→ Email via supportshell → smtp.corp.redhat.com (no Mail.app)"

if [[ "$(uname -s)" == "Darwin" ]]; then
    _sf_clean_agents
    _sf_ensure_plists || exit 1
fi

POLLER_LABEL="com.${USER}.sf-case-poller"
MAILER_LABEL="com.${USER}.local-mailserver"
LAUNCH_DIR="$HOME/Library/LaunchAgents"

# local-mailserver = dashboard UI only (port 8090); mail goes via supportshell SMTP
if _sf_launch_start "$MAILER_LABEL" "$LAUNCH_DIR/${MAILER_LABEL}.plist"; then
    echo "→ Dashboard started"
    _sf_wait_for_port 8090 "Dashboard" || true
else
    echo "→ Dashboard failed — try: ./install.sh"
fi

if _sf_launch_start "$POLLER_LABEL" "$LAUNCH_DIR/${POLLER_LABEL}.plist"; then
    echo "→ SF Case Poller started (every 1 min)"
else
    echo "→ Poller failed — try: ./install.sh"
fi

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║  ✅ Startup complete                          ║"
echo "║                                               ║"
echo "║  Dashboard:  http://localhost:8090             ║"
echo "║  Email:      supportshell SMTP                 ║"
echo "║  Poller log: ~/Library/Logs/sf-case-poller.log║"
echo "╚═══════════════════════════════════════════════╝"
