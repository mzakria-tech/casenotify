#!/bin/bash
# Start SF Case Poller (self-heals LaunchAgents; no dashboard / Mail.app)
# Always re-syncs binaries from this repo so a git pull + ./start.sh picks up fixes.
# For pull+sync+verify in one step: ./update.sh

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=sf-service-lib.sh
source "$REPO_DIR/sf-service-lib.sh"

echo "Starting SF Notification Center..."
echo "→ Email via supportshell → smtp.corp.redhat.com (no Mail.app / no local dashboard)"
echo "→ Syncing scripts from $REPO_DIR → ~/.local/bin"

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
cp "$REPO_DIR/sf-case-poller" "$BIN_DIR/sf-case-poller"
chmod +x "$BIN_DIR/sf-case-poller"
# Remove legacy dashboard if present
rm -f "$BIN_DIR/local-mailserver"

if [[ "$(uname -s)" == "Darwin" ]]; then
    _sf_clean_agents
    _sf_ensure_plists || exit 1
fi

POLLER_LABEL="com.${USER}.sf-case-poller"
LAUNCH_DIR="$HOME/Library/LaunchAgents"

if _sf_launch_start "$POLLER_LABEL" "$LAUNCH_DIR/${POLLER_LABEL}.plist"; then
    echo "→ SF Case Poller started"
else
    echo "→ Poller failed — try: ./update.sh  or  ./install.sh"
fi

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
echo "║  Email:      supportshell SMTP                ║"
echo "║  Update/heal: ./update.sh                     ║"
echo "║  Poller log: ~/Library/Logs/sf-case-poller.log║"
echo "╚═══════════════════════════════════════════════╝"
