#!/bin/bash
# ╔═══════════════════════════════════════════════════════════════╗
# ║  SF Notification Center — Complete Uninstaller               ║
# ╚═══════════════════════════════════════════════════════════════╝

HOME_DIR="$HOME"
BIN_DIR="$HOME_DIR/.local/bin"
STATE_DIR="$HOME_DIR/.local/state"
LOG_DIR="$HOME_DIR/Library/Logs"
LAUNCH_DIR="$HOME_DIR/Library/LaunchAgents"
USER_NAME="${USER:-mzakria}"
POLLER_LABEL="com.${USER_NAME}.sf-case-poller"
MAILER_LABEL="com.${USER_NAME}.local-mailserver"

R='\033[0;31m'; G='\033[0;32m'; B='\033[1;34m'; N='\033[0m'; BOLD='\033[1m'

echo ""
echo -e "${R}╔═══════════════════════════════════════════════════════╗${N}"
echo -e "${R}║   SF Notification Center — Uninstaller               ║${N}"
echo -e "${R}╚═══════════════════════════════════════════════════════╝${N}"

echo -e "\n${B}[1/4]${N} ${BOLD}Stopping services${N}"
LC_DOMAIN="gui/$(id -u)"
launchctl bootout "${LC_DOMAIN}/${POLLER_LABEL}" 2>/dev/null || true
launchctl unload "$LAUNCH_DIR/$POLLER_LABEL.plist" 2>/dev/null || true
echo -e "  ${G}✓${N} SF Poller stopped"

launchctl bootout "${LC_DOMAIN}/${MAILER_LABEL}" 2>/dev/null || true
launchctl unload "$LAUNCH_DIR/$MAILER_LABEL.plist" 2>/dev/null || true
echo -e "  ${G}✓${N} Mail Server LaunchAgent stopped"

pkill -f "local-mailserver" 2>/dev/null
echo -e "  ${G}✓${N} Mail Server process killed"

pkill -f "sf-case-poller" 2>/dev/null
echo -e "  ${G}✓${N} Poller process killed"

echo -e "  ${G}✓${N} All services stopped"

echo -e "\n${B}[2/4]${N} ${BOLD}Removing LaunchAgents${N}"
rm -f "$LAUNCH_DIR/$POLLER_LABEL.plist"
rm -f "$LAUNCH_DIR/$MAILER_LABEL.plist"
echo -e "  ${G}✓${N} LaunchAgent plists removed"

echo -e "\n${B}[3/4]${N} ${BOLD}Removing scripts and state${N}"
rm -f "$BIN_DIR/sf-case-poller"
rm -f "$BIN_DIR/local-mailserver"
rm -f "$STATE_DIR/sf-notification-center.db"
rm -f "$STATE_DIR/sf-poller-config.json"
rm -f "$STATE_DIR/sf-case-status.json"
rm -f "$STATE_DIR/sf-poller-heartbeat.json"
rm -f "$LOG_DIR/sf-case-poller.log"
rm -f /tmp/local-mailserver.log
echo -e "  ${G}✓${N} Scripts, database, config, and logs removed"

echo -e "\n${B}[4/4]${N} ${BOLD}Done${N}"
echo ""
echo -e "${G}╔═══════════════════════════════════════════════════════╗${N}"
echo -e "${G}║  ✅ Completely uninstalled!                           ║${N}"
echo -e "${G}║                                                       ║${N}"
echo -e "${G}║  To reinstall:  ./install.sh                          ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════════╝${N}"
