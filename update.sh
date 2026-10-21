#!/bin/bash
# ╔═══════════════════════════════════════════════════════════════╗
# ║  casenotify — one-command update / heal          ║
# ║  git pull → sync binaries → restart agents → verify GraphQL  ║
# ║  Usage (any laptop):  ./update.sh                            ║
# ╚═══════════════════════════════════════════════════════════════╝
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

G='\033[0;32m'; Y='\033[1;33m'; B='\033[1;34m'; N='\033[0m'; BOLD='\033[1m'

echo ""
echo -e "${BOLD}casenotify — update${N}"
echo -e "  Repo: ${B}${REPO_DIR}${N}"

# 1) Pull latest (ff-only; never rewrite local history)
if [ -d .git ]; then
    echo "→ git pull --ff-only"
    git pull --ff-only origin main 2>/dev/null || git pull --ff-only || {
        echo -e "  ${Y}⚠ git pull failed (offline / diverged) — continuing with local tree${N}"
    }
else
    echo -e "  ${Y}⚠ not a git clone — using files already in ${REPO_DIR}${N}"
fi

# 2) Sync scripts into ~/.local/bin + recreate LaunchAgents + start
# shellcheck source=sf-service-lib.sh
source "$REPO_DIR/sf-service-lib.sh"

BIN_DIR="$HOME/.local/bin"
STATE_DIR="$HOME/.local/state"
mkdir -p "$BIN_DIR" "$STATE_DIR" "$HOME/Library/Logs" "$HOME/Library/LaunchAgents"
cp "$REPO_DIR/sf-case-poller" "$BIN_DIR/sf-case-poller"
cp "$REPO_DIR/local-mailserver" "$BIN_DIR/local-mailserver"
chmod +x "$BIN_DIR/sf-case-poller" "$BIN_DIR/local-mailserver"
[ -f "$REPO_DIR/sf-ssh-setup" ] && cp "$REPO_DIR/sf-ssh-setup" "$BIN_DIR/sf-ssh-setup" && chmod +x "$BIN_DIR/sf-ssh-setup"
echo -e "  ${G}✓${N} binaries synced → $BIN_DIR"

# Resolve supportshell user from config (same as install.sh)
CFG="$STATE_DIR/sf-poller-config.json"
USER_NAME="${USER:-$(whoami)}"
SSH_USER="$USER_NAME"
if [ -f "$CFG" ]; then
    SSH_USER=$(python3 -c "import json; print(json.load(open('$CFG')).get('supportshell_user','$USER_NAME'))" 2>/dev/null || echo "$USER_NAME")
fi
SSH_HOST="${SSH_USER}@supportshell-1.sush-001.prod.us-west-2.aws.redhat.com"

echo "→ Ensuring yank OIDC token on $SSH_HOST"
if ! _sf_ensure_yank_token "$SSH_HOST"; then
    echo -e "  ${Y}⚠ Fix token, then re-run: ./update.sh${N}"
    echo -e "    ssh $SSH_HOST"
    echo -e "    yank --init"
    exit 1
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
    _sf_clean_agents
    _sf_ensure_plists || exit 1
    POLLER_LABEL="com.${USER}.sf-case-poller"
    MAILER_LABEL="com.${USER}.local-mailserver"
    LAUNCH_DIR="$HOME/Library/LaunchAgents"
    _sf_launch_start "$MAILER_LABEL" "$LAUNCH_DIR/${MAILER_LABEL}.plist" || true
    _sf_launch_start "$POLLER_LABEL" "$LAUNCH_DIR/${POLLER_LABEL}.plist" || true
    _sf_wait_for_port 8090 "Dashboard" || true
fi

# 3) Immediate GraphQL poll (surfaces 400 / DISCOVERY_FAILED right here)
echo "→ verifying GraphQL discovery (sf-case-poller --once)"
PYTHON="$(command -v python3 || echo /usr/bin/python3)"
set +e
OUT="$("$PYTHON" "$BIN_DIR/sf-case-poller" --once 2>&1)"
RC=$?
set -e
echo "$OUT" | tail -20
if echo "$OUT" | grep -q "status=OK"; then
    open "http://localhost:8090" 2>/dev/null || true
    echo ""
    echo -e "${G}╔═══════════════════════════════════════════════╗${N}"
    echo -e "${G}║  ✅ Update OK — GraphQL discovery healthy     ║${N}"
    echo -e "${G}║  Dashboard: http://localhost:8090             ║${N}"
    echo -e "${G}╚═══════════════════════════════════════════════╝${N}"
    exit 0
fi

echo ""
echo -e "${Y}╔═══════════════════════════════════════════════╗${N}"
echo -e "${Y}║  Discovery not OK yet                         ║${N}"
echo -e "${Y}║  1) Connect Red Hat VPN                       ║${N}"
echo -e "${Y}║  2) ssh $SSH_HOST                             ║${N}"
echo -e "${Y}║     yank --init                               ║${N}"
echo -e "${Y}║  3) ./update.sh                               ║${N}"
echo -e "${Y}║  Log: ~/Library/Logs/sf-case-poller.log       ║${N}"
echo -e "${Y}╚═══════════════════════════════════════════════╝${N}"
exit "${RC:-1}"
