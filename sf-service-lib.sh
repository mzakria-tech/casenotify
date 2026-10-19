#!/bin/bash
# Shared helpers for install.sh / start.sh — launchctl + Mail.app readiness

_sf_domain() { echo "gui/$(id -u)"; }

_sf_launch_stop() {
    local label="$1"
    local plist="${2:-$HOME/Library/LaunchAgents/${label}.plist}"
    local domain
    domain="$(_sf_domain)"
    # Self-heal: every bootout/unload path is best-effort (no hard fail)
    launchctl bootout "${domain}/${label}" 2>/dev/null || true
    launchctl bootout "$domain" "$plist" 2>/dev/null || true
    launchctl unload "$plist" 2>/dev/null || true
    launchctl remove "$label" 2>/dev/null || true
}

_sf_clean_agents() {
    # Wipe broken LaunchAgents for *this* laptop user ($USER) — no hardcoded names.
    # Safe to run anytime before install/start.
    local user="${USER:-$(whoami)}"
    local domain
    domain="$(_sf_domain)"
    local labels=(
        "com.${user}.sf-case-poller"
        "com.${user}.local-mailserver"
    )
    # Also clear legacy mzakria-labeled agents if someone copied another Mac's plists
    labels+=("com.mzakria.sf-case-poller" "com.mzakria.local-mailserver")

    echo "→ Cleaning LaunchAgents for user '${user}' (self-heal)..."
    local label plist
    for label in "${labels[@]}"; do
        plist="$HOME/Library/LaunchAgents/${label}.plist"
        launchctl bootout "${domain}/${label}" 2>/dev/null || true
        launchctl bootout "$domain" "$plist" 2>/dev/null || true
        launchctl unload "$plist" 2>/dev/null || true
        launchctl remove "$label" 2>/dev/null || true
    done
    pkill -f "local-mailserver" 2>/dev/null || true
    pkill -f "sf-case-poller.*poll" 2>/dev/null || true
    sleep 1
    echo "  ✓ Stale agents cleared"
}

_sf_launch_start() {
    # Start a LaunchAgent with retries (self-heals "Load failed: 5" / stale jobs)
    local label="$1"
    local plist="${2:-$HOME/Library/LaunchAgents/${label}.plist}"
    local domain tries=0
    domain="$(_sf_domain)"

    if [ ! -f "$plist" ]; then
        echo "  ✗ Missing $plist — run ./install.sh first"
        return 1
    fi

    while [ "$tries" -lt 5 ]; do
        tries=$((tries + 1))
        _sf_launch_stop "$label" "$plist"
        # Kill leftover processes for this agent
        case "$label" in
            *local-mailserver*) pkill -f "local-mailserver" 2>/dev/null || true ;;
            *sf-case-poller*)   pkill -f "sf-case-poller.*poll" 2>/dev/null || true ;;
        esac
        sleep 1

        if launchctl bootstrap "$domain" "$plist" 2>/tmp/sf-launchctl.err; then
            launchctl enable "${domain}/${label}" 2>/dev/null || true
            launchctl kickstart -k "${domain}/${label}" 2>/dev/null || true
            sleep 1
            if launchctl print "${domain}/${label}" >/dev/null 2>&1; then
                return 0
            fi
        fi

        # Older macOS fallback
        if launchctl load "$plist" >/tmp/sf-launchctl.err 2>&1; then
            return 0
        fi

        echo "  ⚠ launchctl retry $tries/5 for $label..."
        sleep 2
    done

    echo "  ✗ Could not start $label"
    [ -f /tmp/sf-launchctl.err ] && sed 's/^/    /' /tmp/sf-launchctl.err | head -5
    return 1
}

_sf_mail_status() {
    # OK | NO_ACCOUNTS | NO_ENABLED | TIMEOUT | NOT_RUNNING | ERROR
    if ! pgrep -x "Mail" >/dev/null 2>&1; then
        echo "NOT_RUNNING"
        return
    fi
    local out
    out=$(osascript 2>/dev/null <<'EOF' || true
with timeout of 10 seconds
  tell application "Mail"
    try
      set n to count of accounts
      if n is 0 then return "NO_ACCOUNTS"
      set enabledCount to 0
      repeat with a in every account
        try
          if enabled of a then set enabledCount to enabledCount + 1
        end try
      end repeat
      if enabledCount is 0 then return "NO_ENABLED"
      return "OK"
    on error
      return "ERROR"
    end try
  end tell
end timeout
EOF
)
    case "$out" in
        OK|NO_ACCOUNTS|NO_ENABLED|ERROR) echo "$out" ;;
        *) echo "TIMEOUT" ;;
    esac
}

_sf_wait_for_mail() {
    # Block until Mail.app is running AND has at least one enabled account.
    # Self-heals stuck Mail; prompts user and waits (no silent skip).
    local status tries=0 max_idle_prompts=0
    echo "→ Waiting for Mail.app setup to complete..."
    echo "  1) Sign in to your email account in Mail (Gmail/Red Hat)"
    echo "  2) Dismiss any password / 'Account needs attention' dialogs"
    echo "  3) Leave Mail open — install will continue automatically when ready"
    echo ""

    open -a Mail 2>/dev/null || true

    while true; do
        status="$(_sf_mail_status)"
        case "$status" in
            OK)
                echo "  ✓ Mail.app ready (account configured)"
                return 0
                ;;
            NOT_RUNNING)
                echo "  ⚠ Mail not running — opening Mail.app..."
                pkill -9 -x Mail 2>/dev/null || true
                sleep 1
                open -a Mail 2>/dev/null || true
                sleep 3
                ;;
            TIMEOUT|ERROR)
                tries=$((tries + 1))
                echo "  ⚠ Mail not responding (AppleScript $status) — restarting Mail..."
                pkill -9 -x Mail 2>/dev/null || true
                sleep 2
                open -a Mail 2>/dev/null || true
                sleep 4
                if [ "$tries" -ge 3 ]; then
                    echo ""
                    echo "  Mail is still not responding to automation."
                    echo "  Check: System Settings → Privacy & Security → Automation"
                    echo "  Allow osascript / Terminal / iTerm to control Mail."
                    echo -n "  Press Enter after fixing Mail (or Ctrl-C to abort): "
                    read -r _ || true
                    tries=0
                    open -a Mail 2>/dev/null || true
                    sleep 2
                fi
                ;;
            NO_ACCOUNTS|NO_ENABLED)
                max_idle_prompts=$((max_idle_prompts + 1))
                if [ $((max_idle_prompts % 6)) -eq 1 ]; then
                    echo "  ⚠ No enabled Mail account yet — finish setup in Mail.app..."
                    echo -n "  Press Enter when your Mail account is signed in (or wait): "
                    # Non-blocking-ish: read with timeout if available
                    if read -r -t 15 _; then
                        :
                    fi
                else
                    sleep 5
                fi
                open -a Mail 2>/dev/null || true
                ;;
        esac
        sleep 3
    done
}

_sf_wait_for_port() {
    local port="$1" name="$2" tries=0
    while [ "$tries" -lt 30 ]; do
        if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
            echo "  ✓ $name listening on :$port"
            return 0
        fi
        tries=$((tries + 1))
        sleep 1
    done
    echo "  ⚠ $name not listening on :$port yet"
    return 1
}
