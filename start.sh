#!/bin/bash
# Start all SF Notification Center services

echo "Starting SF Notification Center..."

# Start Mail.app if not running
if ! pgrep -x "Mail" > /dev/null; then
    echo "→ Opening Mail.app..."
    open -a Mail
    sleep 2
fi

# Check Chrome
if ! pgrep -x "Google Chrome" > /dev/null; then
    echo "→ Opening Google Chrome..."
    open -a "Google Chrome"
    sleep 3
fi

POLLER_LABEL="com.${USER}.sf-case-poller"
MAILER_LABEL="com.${USER}.local-mailserver"
DOMAIN="gui/$(id -u)"
LAUNCH_DIR="$HOME/Library/LaunchAgents"

_launch_start() {
    local label="$1"
    local plist="$LAUNCH_DIR/${label}.plist"
    if [ ! -f "$plist" ]; then
        echo "→ Missing $plist — run ./install.sh first"
        return 1
    fi
    # macOS Ventura+: use bootstrap/bootout (load/unload hits "Load failed: 5")
    launchctl bootout "${DOMAIN}/${label}" 2>/dev/null || true
    launchctl bootout "$DOMAIN" "$plist" 2>/dev/null || true
    launchctl unload "$plist" 2>/dev/null || true
    sleep 1
    if launchctl bootstrap "$DOMAIN" "$plist" 2>/dev/null; then
        launchctl enable "${DOMAIN}/${label}" 2>/dev/null || true
        launchctl kickstart -k "${DOMAIN}/${label}" 2>/dev/null || true
        return 0
    fi
    # Fallback for older macOS
    if launchctl load "$plist" 2>/dev/null; then
        return 0
    fi
    echo "→ Failed to start $label"
    return 1
}

_launch_start "$MAILER_LABEL" && echo "→ Mail Server + Dashboard started (port 8090)"
_launch_start "$POLLER_LABEL" && echo "→ SF Case Poller started (every 1 min)"

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║  ✅ All services running!                     ║"
echo "║                                               ║"
echo "║  Dashboard:  http://localhost:8090             ║"
echo "║  Poller log: ~/Library/Logs/sf-case-poller.log║"
echo "╚═══════════════════════════════════════════════╝"
