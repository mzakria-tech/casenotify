#!/bin/bash
# Stop all casenotify services

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=sf-service-lib.sh
source "$REPO_DIR/sf-service-lib.sh"

echo "Stopping casenotify..."

POLLER_LABEL="com.${USER}.sf-case-poller"
MAILER_LABEL="com.${USER}.local-mailserver"
LAUNCH_DIR="$HOME/Library/LaunchAgents"

_sf_launch_stop "$POLLER_LABEL" "$LAUNCH_DIR/${POLLER_LABEL}.plist"
echo "→ SF Case Poller stopped"
_sf_launch_stop "$MAILER_LABEL" "$LAUNCH_DIR/${MAILER_LABEL}.plist"
echo "→ Mail Server + Dashboard stopped"
pkill -f "local-mailserver" 2>/dev/null || true
pkill -f "sf-case-poller.*poll" 2>/dev/null || true

echo ""
echo "All services stopped."
