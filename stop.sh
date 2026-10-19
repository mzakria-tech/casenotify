#!/bin/bash
# Stop all SF Notification Center services

echo "Stopping SF Notification Center..."

POLLER_LABEL="com.${USER}.sf-case-poller"
MAILER_LABEL="com.${USER}.local-mailserver"
DOMAIN="gui/$(id -u)"
LAUNCH_DIR="$HOME/Library/LaunchAgents"

_launch_stop() {
    local label="$1"
    local plist="$LAUNCH_DIR/${label}.plist"
    if launchctl bootout "${DOMAIN}/${label}" 2>/dev/null \
        || launchctl bootout "$DOMAIN" "$plist" 2>/dev/null \
        || launchctl unload "$plist" 2>/dev/null; then
        echo "→ ${label} stopped"
    else
        echo "→ ${label} was not running"
    fi
}

_launch_stop "$POLLER_LABEL"
_launch_stop "$MAILER_LABEL"

echo ""
echo "All services stopped."
