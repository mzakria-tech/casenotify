#!/bin/bash
# Stop SF Notification Center services

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=sf-service-lib.sh
source "$REPO_DIR/sf-service-lib.sh"

echo "Stopping SF Notification Center..."

POLLER_LABEL="com.${USER}.sf-case-poller"
MAILER_LABEL="com.${USER}.local-mailserver"
LAUNCH_DIR="$HOME/Library/LaunchAgents"

_sf_launch_stop "$POLLER_LABEL" "$LAUNCH_DIR/${POLLER_LABEL}.plist"
echo "→ SF Case Poller stopped"
# Legacy dashboard cleanup (removed from product)
_sf_launch_stop "$MAILER_LABEL" "$LAUNCH_DIR/${MAILER_LABEL}.plist"
_sf_launch_stop "com.mzakria.local-mailserver" "$LAUNCH_DIR/com.mzakria.local-mailserver.plist"
rm -f "$LAUNCH_DIR/${MAILER_LABEL}.plist" "$LAUNCH_DIR/com.mzakria.local-mailserver.plist"
pkill -f "local-mailserver" 2>/dev/null || true
pkill -f "sf-case-poller.*poll" 2>/dev/null || true
rm -f "$HOME/.local/bin/local-mailserver"

echo ""
echo "All services stopped."
