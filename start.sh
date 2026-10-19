#!/bin/bash
# Start all SF Notification Center services (self-heals LaunchAgents; no Mail.app)
# Always re-syncs binaries from this repo so a git pull + ./start.sh picks up fixes.
# For pull+sync+verify in one step: ./update.sh

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=sf-service-lib.sh
source "$REPO_DIR/sf-service-lib.sh"

echo "Starting SF Notification Center..."
echo "→ Email via supportshell → smtp.corp.redhat.com (no Mail.app)"
echo "→ Syncing scripts from $REPO_DIR → ~/.local/bin"

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
cp "$REPO_DIR/sf-case-poller" "$BIN_DIR/sf-case-poller"
cp "$REPO_DIR/local-mailserver" "$BIN_DIR/local-mailserver"
chmod +x "$BIN_DIR/sf-case-poller" "$BIN_DIR/local-mailserver"

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
    echo "→ Dashboard failed — try: ./update.sh  or  ./install.sh"
fi

if _sf_launch_start "$POLLER_LABEL" "$LAUNCH_DIR/${POLLER_LABEL}.plist"; then
    echo "→ SF Case Poller started"
else
    echo "→ Poller failed — try: ./update.sh  or  ./install.sh"
fi

# One-shot GraphQL check so broken discovery is visible at start (not only in log)
PYTHON="$(command -v python3 || echo /usr/bin/python3)"
echo "→ GraphQL check (sf-case-poller --once)..."
ONCE_OUT="$("$PYTHON" "$BIN_DIR/sf-case-poller" --once 2>&1)" || true
echo "$ONCE_OUT" | tail -5
if ! echo "$ONCE_OUT" | grep -q "status=OK"; then
    echo ""
    echo "⚠ Discovery not OK — heal with:"
    echo "    cd \"$REPO_DIR\" && ./update.sh"
fi

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║  ✅ Startup complete                          ║"
echo "║                                               ║"
echo "║  Dashboard:  http://localhost:8090            ║"
echo "║  Email:      supportshell SMTP                ║"
echo "║  Update/heal: ./update.sh                     ║"
echo "║  Poller log: ~/Library/Logs/sf-case-poller.log║"
echo "╚═══════════════════════════════════════════════╝"
