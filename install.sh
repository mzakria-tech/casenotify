#!/bin/bash
# ╔═══════════════════════════════════════════════════════════════╗
# ║  casenotify — One-command installer              ║
# ║  Works on macOS (LaunchAgents) and Linux (systemd)           ║
# ║  GraphQL-powered • No browser needed • 24/7 on any server   ║
# ╚═══════════════════════════════════════════════════════════════╝
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HOME_DIR="$HOME"
BIN_DIR="$HOME_DIR/.local/bin"
STATE_DIR="$HOME_DIR/.local/state"
PYTHON="$(command -v python3 || true)"
USER_NAME="${USER:-$(whoami)}"

# Detect OS
IS_MAC=0; IS_LINUX=0
case "$(uname -s)" in
    Darwin) IS_MAC=1 ;;
    Linux)  IS_LINUX=1 ;;
esac

if [ "$IS_MAC" -eq 1 ]; then
    LOG_DIR="$HOME_DIR/Library/Logs"
    LAUNCH_DIR="$HOME_DIR/Library/LaunchAgents"
else
    LOG_DIR="$HOME_DIR/.local/state/logs"
    SYSTEMD_DIR="$HOME_DIR/.config/systemd/user"
fi

POLLER_LABEL="com.${USER_NAME}.sf-case-poller"
MAILER_LABEL="com.${USER_NAME}.local-mailserver"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[1;34m'; N='\033[0m'; BOLD='\033[1m'

ok()   { echo -e "  ${G}✓${N} $1"; }
warn() { echo -e "  ${Y}⚠${N} $1"; }
fail() { echo -e "  ${R}✗${N} $1"; }
step() { echo -e "\n${B}[$1]${N} ${BOLD}$2${N}"; }

# shellcheck source=sf-service-lib.sh
source "$REPO_DIR/sf-service-lib.sh"

# ═══════════════════════════════════════════════════════════════
# UNINSTALL — ./install.sh uninstall
# ═══════════════════════════════════════════════════════════════
if [ "${1:-}" = "uninstall" ]; then
    echo ""
    echo -e "${R}╔═══════════════════════════════════════════════════════╗${N}"
    echo -e "${R}║   casenotify — Uninstaller               ║${N}"
    echo -e "${R}╚═══════════════════════════════════════════════════════╝${N}"

    step "1/4" "Stopping services"
    if [ "$IS_MAC" -eq 1 ]; then
        _LC_DOMAIN="gui/$(id -u)"
        launchctl bootout "${_LC_DOMAIN}/${POLLER_LABEL}" 2>/dev/null || true
        launchctl bootout "${_LC_DOMAIN}/${MAILER_LABEL}" 2>/dev/null || true
        launchctl unload "$LAUNCH_DIR/$POLLER_LABEL.plist" 2>/dev/null || true
        launchctl unload "$LAUNCH_DIR/$MAILER_LABEL.plist" 2>/dev/null || true
    else
        systemctl --user stop sf-case-poller 2>/dev/null || true
        systemctl --user stop sf-mailserver 2>/dev/null || true
        systemctl --user disable sf-case-poller 2>/dev/null || true
        systemctl --user disable sf-mailserver 2>/dev/null || true
    fi
    pkill -f "sf-case-poller" 2>/dev/null || true
    pkill -f "local-mailserver" 2>/dev/null || true
    ok "All services stopped"

    step "2/4" "Removing service configs"
    if [ "$IS_MAC" -eq 1 ]; then
        rm -f "$LAUNCH_DIR/$POLLER_LABEL.plist"
        rm -f "$LAUNCH_DIR/$MAILER_LABEL.plist"
        ok "LaunchAgent plists removed"
    else
        rm -f "$SYSTEMD_DIR/sf-case-poller.service"
        rm -f "$SYSTEMD_DIR/sf-mailserver.service"
        systemctl --user daemon-reload 2>/dev/null || true
        ok "Systemd units removed"
    fi

    step "3/4" "Removing scripts and state"
    rm -f "$BIN_DIR/sf-case-poller"
    rm -f "$BIN_DIR/local-mailserver"
    rm -f "$BIN_DIR/sf-ssh-setup"
    rm -f "$STATE_DIR/casenotify.db"
    rm -f "$STATE_DIR/sf-poller-config.json"
    rm -f "$STATE_DIR/sf-case-status.json"
    rm -f "$STATE_DIR/sf-poller-heartbeat.json"
    rm -f "$LOG_DIR/sf-case-poller.log" 2>/dev/null
    rm -f /tmp/local-mailserver.log
    ok "Scripts, database, config, and logs removed"

    step "4/4" "Done"
    echo ""
    echo -e "${G}╔═══════════════════════════════════════════════════════╗${N}"
    echo -e "${G}║  ${BOLD}✅ Completely uninstalled!${N}${G}                             ║${N}"
    echo -e "${G}║                                                       ║${N}"
    echo -e "${G}║  To reinstall:  ${BOLD}./install.sh${N}${G}                           ║${N}"
    echo -e "${G}╚═══════════════════════════════════════════════════════╝${N}"
    exit 0
fi

OS_LABEL="macOS (LaunchAgents)"
[ "$IS_LINUX" -eq 1 ] && OS_LABEL="Linux (systemd)"

echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════════════╗${N}"
echo -e "${BOLD}║   casenotify — Automatic Installer       ║${N}"
echo -e "${BOLD}║   GraphQL-powered • No browser needed                ║${N}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════════╝${N}"

# ────────────────────────────────────────────────────────────────
step "1/4" "Setup"
# ────────────────────────────────────────────────────────────────

if [ -z "$PYTHON" ]; then
    fail "Python3 not found. Install: brew install python3"
    exit 1
fi
if ! command -v ssh >/dev/null 2>&1; then
    fail "SSH not found"
    exit 1
fi

# aiosmtpd is only needed for the local dashboard SMTP catcher — never abort install
if ! "$PYTHON" -c "import aiosmtpd" 2>/dev/null; then
    warn "Installing aiosmtpd (dashboard)..."
    set +e
    "$PYTHON" -m pip install --user --quiet aiosmtpd 2>/tmp/sf-pip.err \
        || pip3 install --user --quiet aiosmtpd 2>>/tmp/sf-pip.err \
        || "$PYTHON" -m pip install --break-system-packages --user --quiet aiosmtpd 2>>/tmp/sf-pip.err
    set -e
    if ! "$PYTHON" -c "import aiosmtpd" 2>/dev/null; then
        warn "aiosmtpd not installed — dashboard may fail; email still works via supportshell SMTP"
        cat /tmp/sf-pip.err 2>/dev/null | sed 's/^/    /' | head -5 || true
    else
        ok "aiosmtpd installed"
    fi
fi

mkdir -p "$BIN_DIR" "$STATE_DIR" "$LOG_DIR" "$LAUNCH_DIR"
cp "$REPO_DIR/sf-case-poller" "$BIN_DIR/sf-case-poller"
cp "$REPO_DIR/local-mailserver" "$BIN_DIR/local-mailserver"
cp "$REPO_DIR/sf-ssh-setup" "$BIN_DIR/sf-ssh-setup" 2>/dev/null || true
chmod +x "$BIN_DIR/sf-case-poller" "$BIN_DIR/local-mailserver"
[ -f "$BIN_DIR/sf-ssh-setup" ] && chmod +x "$BIN_DIR/sf-ssh-setup"

# Add to PATH in shell rc
SHELL_RC="$HOME_DIR/.bashrc"
if [ -f "$HOME_DIR/.zshrc" ]; then
    SHELL_RC="$HOME_DIR/.zshrc"
fi
if ! grep -q '.local/bin' "$SHELL_RC" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
fi
export PATH="$BIN_DIR:$PATH"
ok "Python + scripts ready"

CFG="$STATE_DIR/sf-poller-config.json"
if [ ! -f "$CFG" ]; then
    cat > "$CFG" <<CFGEOF
{
  "notify_email": "${USER_NAME}@redhat.com",
  "supportshell_user": "$USER_NAME"
}
CFGEOF
fi
SSH_USER=$("$PYTHON" -c "import json; print(json.load(open('$CFG')).get('supportshell_user','$USER_NAME'))" 2>/dev/null || echo "$USER_NAME")
SSH_HOST="${SSH_USER}@supportshell-1.sush-001.prod.us-west-2.aws.redhat.com"
SSH_CTRL="/tmp/sf-ssh-ctrl-${USER_NAME}"
ok "Scripts, config, PATH ready"

# ── Auto SSH setup (no manual ssh-copy-id / kinit needed) ──
ssh_ok() {
    ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=no \
        -o PreferredAuthentications=publickey,gssapi-with-mic \
        "$SSH_HOST" "echo SSH_OK" 2>/dev/null | grep -q SSH_OK
}

ensure_ssh_key() {
    mkdir -p "$HOME_DIR/.ssh"
    chmod 700 "$HOME_DIR/.ssh"
    if [ ! -f "$HOME_DIR/.ssh/id_ed25519" ] && [ ! -f "$HOME_DIR/.ssh/id_rsa" ]; then
        ssh-keygen -t ed25519 -N "" -f "$HOME_DIR/.ssh/id_ed25519" -q
        ok "Generated SSH key (~/.ssh/id_ed25519)"
    fi
}

install_key_on_supportshell() {
    # Prefer Kerberos if available, else password auth — user only enters password once
    # Do NOT hide errors — user must see password prompt / failure reason
    if command -v klist >/dev/null 2>&1 && klist -s 2>/dev/null; then
        ssh-copy-id -o PreferredAuthentications=gssapi-with-mic,password \
            -o StrictHostKeyChecking=no "$SSH_HOST" && return 0
    fi
    ssh-copy-id -o PreferredAuthentications=password,keyboard-interactive,publickey \
        -o StrictHostKeyChecking=no -o NumberOfPasswordPrompts=3 "$SSH_HOST"
}

step "1b/4" "SSH to supportshell (automatic — one password if needed)"
echo -e "  Target: ${BOLD}$SSH_HOST${N}"
echo -e "  ${Y}Connect Red Hat VPN first. Install will not finish until SSH works.${N}"
ensure_ssh_key

# Confirm supportshell username once (macOS $USER must match RH login)
if ! ssh_ok; then
    echo -e "  Using supportshell user: ${BOLD}$SSH_USER${N}"
    echo -n "  Press Enter to keep, or type your Red Hat username: "
    read -r NEW_USER || true
    if [ -n "$NEW_USER" ]; then
        SSH_USER="$NEW_USER"
        SSH_HOST="${SSH_USER}@supportshell-1.sush-001.prod.us-west-2.aws.redhat.com"
        "$PYTHON" -c "import json; p='$CFG'; d=json.load(open(p)); d['supportshell_user']='$SSH_USER'; json.dump(d, open(p,'w'), indent=2)" 2>/dev/null || true
        ok "Updated supportshell user to $SSH_USER"
    fi
fi

# Loop until SSH works — password may be asked once; after that app runs alone
SSH_SETUP_TRIES=0
while ! ssh_ok; do
    SSH_SETUP_TRIES=$((SSH_SETUP_TRIES + 1))
    if [ "$SSH_SETUP_TRIES" -gt 3 ]; then
        fail "SSH still failing after 3 attempts"
        echo -e "    ${Y}Connect Red Hat VPN, confirm username, then re-run: ./install.sh${N}"
        exit 1
    fi
    warn "SSH not ready (attempt $SSH_SETUP_TRIES/3) — fixing automatically..."

    if command -v kinit >/dev/null 2>&1 && ! klist -s 2>/dev/null; then
        echo -e "  ${Y}Enter Red Hat password (Kerberos) — once only:${N}"
        kinit "${SSH_USER}@REDHAT.COM" || true
    fi

    echo -e "  ${Y}Installing SSH key on supportshell — enter Red Hat password if asked:${N}"
    install_key_on_supportshell || true

    if ssh_ok; then
        break
    fi
    echo -e "  ${R}Not connected yet. Check VPN is ON, then try again...${N}"
    sleep 2
done
ok "SSH ready — application will run automatically from here"

# GraphQL needs OIDC on supportshell — run yank --init if missing/expired
step "1c/4" "Supportshell OIDC token (yank --init if needed)"
if ! _sf_ensure_yank_token "$SSH_HOST"; then
    fail "OIDC token required for GraphQL case discovery"
    echo -e "    ${Y}VPN on → ssh $SSH_HOST → yank --init → re-run ./install.sh${N}"
    exit 1
fi
ok "Supportshell GraphQL token ready"

# Pre-warm SSH + first poll in background (runs during service startup)
if ssh_ok; then
    (ssh -o ControlMaster=yes -o ControlPath="$SSH_CTRL" \
        -o ControlPersist=300 -o ConnectTimeout=10 -o BatchMode=yes \
        -N "$SSH_HOST" &>/dev/null &)
    "$PYTHON" "$BIN_DIR/sf-case-poller" --once &>/dev/null &
fi

# ────────────────────────────────────────────────────────────────
step "2/5" "Clean broken agents (email = supportshell SMTP, no Mail.app)"
# ────────────────────────────────────────────────────────────────

if [ "$IS_MAC" -eq 1 ]; then
    _sf_clean_agents
    ok "Stale LaunchAgents cleared — mail will use supportshell SMTP"
else
    ok "Linux: no LaunchAgents to clean"
fi

# ────────────────────────────────────────────────────────────────
step "3/5" "Starting services"
# ────────────────────────────────────────────────────────────────

if [ "$IS_MAC" -eq 1 ]; then
    # ── macOS: LaunchAgents ──
    mkdir -p "$LAUNCH_DIR"

    SSH_SOCK="${SSH_AUTH_SOCK:-}"
    [ -z "$SSH_SOCK" ] && SSH_SOCK=$(ls /private/tmp/com.apple.launchd.*/Listeners 2>/dev/null | head -1 || echo "")

    cat > "$LAUNCH_DIR/$MAILER_LABEL.plist" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$MAILER_LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$PYTHON</string><string>$BIN_DIR/local-mailserver</string></array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key><string>$HOME_DIR</string>
        <key>USER</key><string>$USER_NAME</string>
        <key>SSH_AUTH_SOCK</key><string>$SSH_SOCK</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>/tmp/local-mailserver.log</string>
    <key>StandardErrorPath</key><string>/tmp/local-mailserver.log</string>
</dict>
</plist>
PLISTEOF
    if _sf_launch_start "$MAILER_LABEL" "$LAUNCH_DIR/$MAILER_LABEL.plist"; then
        _sf_wait_for_port 8090 "Dashboard" || true
        ok "Dashboard started (port 8090) — email uses supportshell SMTP"
    else
        fail "Could not start dashboard LaunchAgent"
        exit 1
    fi

    cat > "$LAUNCH_DIR/$POLLER_LABEL.plist" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$POLLER_LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$PYTHON</string><string>$BIN_DIR/sf-case-poller</string><string>poll</string></array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>SF_POLL_INTERVAL</key><string>60</string>
        <key>HOME</key><string>$HOME_DIR</string>
        <key>USER</key><string>$USER_NAME</string>
        <key>SSH_AUTH_SOCK</key><string>$SSH_SOCK</string>
    </dict>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>5</integer>
    <key>StandardOutPath</key><string>$LOG_DIR/sf-case-poller.log</string>
    <key>StandardErrorPath</key><string>$LOG_DIR/sf-case-poller.log</string>
</dict>
</plist>
PLISTEOF
    if _sf_launch_start "$POLLER_LABEL" "$LAUNCH_DIR/$POLLER_LABEL.plist"; then
        ok "SF case poller started (every 60s)"
    else
        fail "Could not start poller LaunchAgent"
        exit 1
    fi

else
    # ── Linux: systemd user services (24/7 on server) ──
    mkdir -p "$SYSTEMD_DIR"
    pkill -f "local-mailserver" 2>/dev/null || true
    pkill -f "sf-case-poller.*poll" 2>/dev/null || true

    cat > "$SYSTEMD_DIR/sf-mailserver.service" <<SVCEOF
[Unit]
Description=casenotify Dashboard + SMTP
After=network.target

[Service]
Type=simple
ExecStart=$PYTHON $BIN_DIR/local-mailserver
Restart=always
RestartSec=5
Environment=HOME=$HOME_DIR

[Install]
WantedBy=default.target
SVCEOF

    cat > "$SYSTEMD_DIR/sf-case-poller.service" <<SVCEOF
[Unit]
Description=SF Case Poller (GraphQL via supportshell)
After=network.target sf-mailserver.service

[Service]
Type=simple
ExecStart=$PYTHON $BIN_DIR/sf-case-poller poll
Restart=always
RestartSec=10
Environment=HOME=$HOME_DIR
Environment=SF_POLL_INTERVAL=60

[Install]
WantedBy=default.target
SVCEOF

    systemctl --user daemon-reload
    systemctl --user enable sf-mailserver sf-case-poller
    systemctl --user start sf-mailserver
    systemctl --user start sf-case-poller
    ok "Dashboard started (port 8090)"
    ok "SF case poller started (every 60s, auto-restart on failure)"

    if command -v loginctl &>/dev/null; then
        loginctl enable-linger "$USER_NAME" 2>/dev/null || true
        ok "Linger enabled — services run 24/7 even after logout"
    fi
fi

# ────────────────────────────────────────────────────────────────
step "4/5" "Opening dashboard"
# ────────────────────────────────────────────────────────────────

for i in 1 2 3 4 5 6 7 8 9 10; do
    curl -s -o /dev/null http://localhost:8090 2>/dev/null && break
    sleep 1
done

[ "$IS_MAC" -eq 1 ] && open "http://localhost:8090" 2>/dev/null || true

ok "Dashboard ready — cases loading in background"
ok "http://localhost:8090"

# ────────────────────────────────────────────────────────────────
step "5/5" "Done"
# ────────────────────────────────────────────────────────────────

echo ""
echo -e "${G}╔═══════════════════════════════════════════════════════╗${N}"
echo -e "${G}║  ${BOLD}✅ Installation complete!${N}${G}                              ║${N}"
echo -e "${G}║                                                       ║${N}"
echo -e "${G}║  Dashboard:   ${BOLD}http://localhost:8090${N}${G}                    ║${N}"
echo -e "${G}║  Email:       ${BOLD}supportshell → smtp.corp.redhat.com${N}${G}     ║${N}"
echo -e "${G}║  Update/heal: ${BOLD}./update.sh${N}${G}                              ║${N}"
echo -e "${G}║  Uninstall:   ${BOLD}./install.sh uninstall${N}${G}                   ║${N}"
echo -e "${G}║                                                       ║${N}"
echo -e "${G}║  Data source: Red Hat GraphQL API (no browser needed) ║${N}"
echo -e "${G}║  Polling:     Every 60 seconds • Runs 24/7            ║${N}"
echo -e "${G}╚═══════════════════════════════════════════════════════╝${N}"
