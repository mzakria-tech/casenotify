# SF Notification Center — Technical Documentation

Detailed tech stack, architecture, components, auth, data flow, and operations for engineers installing or maintaining this project.

**Repo:** https://github.com/mzakria-tech/sf-notification-center  
**Audience:** Red Hat OpenShift Support engineers (macOS primary; Linux systemd supported)

---

## 1. What it does

Monitors **your open Salesforce support cases**, detects status / comment changes, and:

1. Sends **email alerts** via Red Hat corporate SMTP (through supportshell)
2. Shows a **macOS notification banner**
3. Displays a **local web dashboard** at `http://localhost:8090`

It does **not** scrape Chrome, use Mail.app, or talk to Salesforce from the laptop directly. All Salesforce/GraphQL access runs on **supportshell** over SSH using an OIDC token from `yank --init`.

---

## 2. High-level architecture

```
┌─────────────────────┐     SSH + remote Python      ┌──────────────────────────────┐
│  Engineer laptop    │ ───────────────────────────► │  supportshell (AWS)          │
│                     │                              │                              │
│  sf-case-poller     │   OIDC refresh + GraphQL     │  ~/.yank/oidc-tokens.json    │
│  (LaunchAgent)      │ ◄─────────────────────────── │  vpn.graphql.redhat.com      │
│         │           │                              │  smtp.corp.redhat.com:25     │
│         ▼           │                              └──────────────────────────────┘
│  SQLite + JSON      │
│  state / heartbeat  │
│         │           │
│         ├──► Email (via supportshell SMTP)
│         ├──► macOS banner (osascript)
│         └──► local-mailserver :8090 (dashboard UI)
└─────────────────────┘
```

**Poll loop (default):** every **60 seconds** (LaunchAgent sets `SF_POLL_INTERVAL=60`; code default env is 300 if unset).

---

## 3. Tech stack

| Layer | Technology | Role |
|--------|------------|------|
| Language | **Python 3** (stdlib-first) | Poller + dashboard |
| Data store | **SQLite3** | Cases, events, notification queue, poll history |
| Compat state | **JSON** files | Dashboard reads case snapshot + heartbeat |
| Remote exec | **OpenSSH** (`ssh` + remote `python3`) | GraphQL + SMTP on supportshell |
| Case API | **Red Hat GraphQL** `https://vpn.graphql.redhat.com` | Case discovery + comments |
| Auth | **OIDC device flow** via `yank --init` | Refresh token → access token |
| SSO | **Red Hat SSO** (`sso.redhat.com`) | Token refresh (`cee-supportshell-deviceauth`) |
| Email | **SMTP** `smtp.corp.redhat.com:25` (from supportshell) | Alert delivery |
| Local UI | **http.server** (`HTTPServer` + `BaseHTTPRequestHandler`) | Dashboard HTML/JSON API |
| Optional local SMTP | **aiosmtpd** (optional) | Catcher on `:2525` for UI preview only |
| Process mgmt (macOS) | **launchd / LaunchAgents** | KeepAlive poller + dashboard |
| Process mgmt (Linux) | **systemd --user** | Same services |
| Install / ops | **Bash** (`install.sh`, `start.sh`, `update.sh`, …) | Install, heal, yank, open browser |
| VPN | **Red Hat VPN** | Required for supportshell + GraphQL |

### Python dependencies

| Package | Required? | Used by |
|---------|-----------|---------|
| stdlib only (`sqlite3`, `urllib`, `smtplib`, `subprocess`, …) | **Yes** | `sf-case-poller` |
| `aiosmtpd` | Optional | `local-mailserver` local SMTP catcher; UI works without it |

No Node.js, no Docker, no Chrome automation, no Mail.app AppleScript for sending mail.

---

## 4. Repository layout

| Path | Description |
|------|-------------|
| `sf-case-poller` | Main poller CLI + long-running `poll` service |
| `local-mailserver` | Dashboard web UI (`:8090`) + optional SMTP (`:2525`) + watchdog |
| `sf-service-lib.sh` | Shared bash: launchctl helpers, yank OIDC ensure, Chrome device URL open |
| `install.sh` | First-time install (SSH, yank, LaunchAgents, open dashboard) |
| `update.sh` | `git pull` → sync bins → yank if needed → restart → verify → open UI |
| `start.sh` | Sync bins → start agents → GraphQL `--once` → **open http://localhost:8090** |
| `stop.sh` | Stop poller + dashboard |
| `uninstall.sh` / `install.sh uninstall` | Remove agents, bins, state (as configured) |
| `sf-ssh-setup` | Helper to fix SSH key to supportshell |
| `com.mzakria.*.plist` | Example plists (runtime uses `com.$USER.*`) |
| `README.md` | Quick start |
| `TECH.md` | This document |

---

## 5. Runtime components

### 5.1 `sf-case-poller`

**Role:** Discover cases, detect changes, queue and send notifications.

**Entry points:**

| Command | Purpose |
|---------|---------|
| `sf-case-poller poll` | Long-running loop (LaunchAgent) |
| `sf-case-poller --once` | Single poll cycle |
| `sf-case-poller status` | Config / SSH summary |
| `sf-case-poller health` | SMTP, SSH, DB, dashboard, heartbeat |
| `sf-case-poller test-email` | Test SMTP + banner |
| `sf-case-poller dashboard` | `open http://localhost:8090` |
| `sf-case-poller logs` | `tail -f` poller log |
| `sf-case-poller history` | Recent notifications |

**Reliability features:**

- Event hashing / deduplication
- Notification retry with backoff: `10s, 30s, 120s, 300s`
- SSH circuit breaker: open after 3 failures, reset after 15 minutes
- Startup reconciliation (avoid false alerts after restart)
- Heartbeat file for dashboard / watchdog
- Structured UTC logs

### 5.2 `local-mailserver`

**Role:** Local ops UI only. **Not** used for real outbound alert email.

| Port | Service |
|------|---------|
| **8090** | Web dashboard (HTML + `/api/*` JSON) |
| **2525** | Optional aiosmtpd catcher (preview); real mail = supportshell SMTP |

**Dashboard shows:**

- Service health (poller, SSH/GraphQL via heartbeat, VPN hint, etc.)
- Tracked cases (from `sf-case-status.json`)
- Activity / poller log tail
- Self-healing watchdog log
- Heal command when GraphQL discovery fails

**Watchdog (background thread ~60s):** restarts poller LaunchAgent if down, triggers poll if state JSON missing, rotates huge logs, resets stuck notification retries, surfaces GraphQL `DISCOVERY_FAILED` + heal command.

### 5.3 LaunchAgents (macOS)

Labels (per laptop user):

- `com.$USER.sf-case-poller`
- `com.$USER.local-mailserver`

Installed under `~/Library/LaunchAgents/`.  
`KeepAlive` + `ThrottleInterval`; env includes `HOME`, `USER`, `SSH_AUTH_SOCK`, `SF_POLL_INTERVAL=60`.

Started with modern `launchctl bootstrap` / `kickstart` (fallback `load`).

### 5.4 Linux (optional)

systemd user units:

- `sf-case-poller.service`
- `sf-mailserver.service`

Linger recommended so services survive logout.

---

## 6. Authentication & GraphQL

### 6.1 Why supportshell?

Laptop cannot reliably call GraphQL/SMTP on the corp network path used by CEE tools. Supportshell has:

- `yank` / hydra-mcp token locations
- Access to `vpn.graphql.redhat.com`
- Relay to `smtp.corp.redhat.com`

### 6.2 OIDC (`yank --init`)

1. Install/update checks for a usable refresh token on supportshell:
   - `~/.cache/hydra-mcp/tokens/redhat-sso-token.json`, or
   - `~/.yank/oidc-tokens.json`
2. If missing/expired → `ssh -tt … 'yank --init'`
3. Device URL `https://sso.redhat.com/device?user_code=…` is **auto-opened in Chrome** on the Mac
4. User completes Red Hat SSO; yank saves the token

Token refresh uses:

- Grant: `refresh_token`
- Client: `cee-supportshell-deviceauth`
- Endpoint: `https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token`

### 6.3 GraphQL client requirements

Requests to `https://vpn.graphql.redhat.com` **must** include:

```
apollographql-client-name: redhat-hydra-mcp-server
apollographql-client-version: 0.1.0
Authorization: Bearer <access_token>
Content-Type: application/json
```

Missing Apollo headers → **HTTP 400 Bad Request**.

### 6.4 Owner / case discovery

1. Resolve Salesforce User Id via:
   ```graphql
   query { redhat_support_uiapi { currentUser { Id } } }
   ```
   (replaces removed `Case_Owner_Alias__c`)
2. Fallback: cached `sf_owner_id`, hydra `sf-owner-id.txt`, or OwnerId from a known case number
3. List open cases:
   ```graphql
   query ListMyCases($oid: ID!) {
     redhat_support_uiapi {
       query {
         RedHatSupportCase(
           where: { OwnerId: { eq: $oid }, IsClosed: { eq: false } }
           first: 50
           orderBy: { LastModifiedDate: { order: DESC } }
         ) { ... }
       }
     }
   }
   ```
   Note: `OwnerId` filter variable type is **`ID!`**, not `String!` (String! → validation 400).
4. Comments fetched per case via `CaseComments__r` (with fallback query if shape fails)

---

## 7. Email & notifications

| Channel | Mechanism |
|---------|-----------|
| **smtp** | SSH to supportshell → `smtplib.SMTP("smtp.corp.redhat.com", 25)` |
| **banner** | Local macOS notification (osascript / system banner) |

**From header:** short per-laptop alias, e.g. `mzakria <mzakria@redhat.com>` (`notify_from_alias` / supportshell user / `$USER`).

**Mail.app:** not required; safe to quit.

**Local `:2525`:** optional UI-only catcher; production alerts never depend on it.

---

## 8. Data & file locations

| Path | Purpose |
|------|---------|
| `~/.local/bin/sf-case-poller` | Installed poller |
| `~/.local/bin/local-mailserver` | Installed dashboard |
| `~/.local/state/sf-poller-config.json` | Config (`notify_email`, `supportshell_user`, `sf_owner_id`, …) |
| `~/.local/state/sf-notification-center.db` | SQLite DB |
| `~/.local/state/sf-case-status.json` | Case snapshot for dashboard |
| `~/.local/state/sf-poller-heartbeat.json` | Last successful poll / status |
| `~/Library/Logs/sf-case-poller.log` | Poller log (macOS) |
| `/tmp/local-mailserver.log` | Dashboard stdout/stderr |
| `~/Library/LaunchAgents/com.$USER.*.plist` | launchd unit files |

### SQLite tables (summary)

- **cases** — tracked case id, number, status, subject, owner, comment metadata, …
- **events** — detected changes (hashed for dedupe)
- **notifications** — queue (`PENDING` / `RETRY` / sent) with retry_count
- **poll_runs** — poll history / errors
- **meta** — key/value (e.g. initialized flag)

---

## 9. Configuration

### `~/.local/state/sf-poller-config.json` (example)

```json
{
  "notify_email": "you@redhat.com",
  "supportshell_user": "your-rh-username",
  "sf_owner_id": "005……………",
  "notify_from_alias": "shortname"
}
```

### Environment variables

| Variable | Meaning |
|----------|---------|
| `SF_POLL_INTERVAL` | Seconds between polls (LaunchAgent uses `60`) |
| `SUPPORTSHELL_USER` / config `supportshell_user` | SSH user on supportshell |
| `SUPPORTSHELL_HOST` | Override SSH host |
| `SF_NOTIFY_EMAIL` | Override notify address |
| `SF_NOTIFY_FROM_ALIAS` | Override From display name |
| `SF_NOTIFY_HEAL_CMD` | Override heal command shown on discovery failure |
| `SF_CASE_LIST_URL` | Legacy list URL field (GraphQL path does not need Chrome) |
| `SSH_AUTH_SOCK` | Agent socket (LaunchAgent may refresh dynamically) |

---

## 10. Install / update / heal flow

### Fresh Mac

```bash
# Red Hat VPN on
cd ~/Desktop
git clone https://github.com/mzakria-tech/sf-notification-center.git
cd sf-notification-center
./install.sh
```

`install.sh` will:

1. Copy scripts to `~/.local/bin`
2. Ensure SSH to supportshell (password / Kerberos once if needed)
3. Run **`yank --init`** if OIDC missing (opens Chrome for device login)
4. Create LaunchAgents, start poller + dashboard
5. **`open http://localhost:8090`**

### Update / heal

```bash
cd ~/Desktop/sf-notification-center
./update.sh
```

=`git pull` → sync bins → yank if needed → restart → `sf-case-poller --once` → open dashboard.

### Start only

```bash
./start.sh
```

Opens the dashboard as soon as port **8090** is listening.

### Heal command (embedded in code)

On `DISCOVERY_FAILED`, logs / heartbeat / dashboard show:

```bash
cd ~/Desktop/sf-notification-center && ./update.sh
```

---

## 11. Network & security notes

- **VPN required** for SSH to supportshell and GraphQL.
- Tokens live on **supportshell** home dirs; treat as secrets (do not commit / paste).
- GraphQL queries run as the engineer’s OIDC identity (own cases).
- Dashboard binds `0.0.0.0:8090` locally — use on trusted networks / localhost.
- No pull secrets or Salesforce passwords stored in the repo.

---

## 12. Failure modes & troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `HTTP 400` GraphQL | Missing Apollo headers, `String!` OwnerId, or stale binary | `./update.sh` |
| `DISCOVERY_FAILED` / empty cases | No/expired OIDC, SSH down, VPN off | VPN → `./update.sh` (yank --init) |
| Dashboard not opening | Agent not started | `./start.sh` or `open http://localhost:8090` |
| No email | SSH/SMTP from supportshell failing | `sf-case-poller health` / `test-email` |
| LaunchAgent load error 5 | Stale launchd state | `./stop.sh` then `./start.sh` (uses bootstrap) |
| Port 8090 down | `local-mailserver` not running | `./start.sh` |

Logs:

```bash
tail -f ~/Library/Logs/sf-case-poller.log
tail -f /tmp/local-mailserver.log
sf-case-poller health
```

---

## 13. End-to-end data flow (one poll)

1. LaunchAgent wakes `sf-case-poller poll` (or `--once`).
2. Poller SSHs to supportshell and runs embedded Python.
3. Remote code refreshes OIDC access token.
4. Resolves `currentUser.Id` → lists open `RedHatSupportCase` + comment metadata.
5. Local poller diffs vs SQLite → creates **events**.
6. Events enqueue **notifications** → SMTP (supportshell) + banner.
7. Writes heartbeat + `sf-case-status.json`.
8. Dashboard refreshes from JSON / log / heartbeat (browser auto-open on start).

---

## 14. Version history (conceptual)

| Era | Approach |
|-----|----------|
| v1/v2 | Chrome AppleScript scrape + Mail.app |
| **v3 (current)** | Chrome-free GraphQL via supportshell SSH; supportshell SMTP; local dashboard UI |

---

## 15. Related Red Hat systems

| System | Use |
|--------|-----|
| Supportshell | SSH bastion / CEE shell |
| yank | Attachments + OIDC init |
| hydra-mcp token cache | Alternate token path |
| vpn.graphql.redhat.com | Salesforce UI API GraphQL gateway |
| smtp.corp.redhat.com | Corporate mail relay |
| sso.redhat.com | OIDC |

---

## 16. Maintainer notes

- Prefer stdlib; avoid adding heavy frameworks unless necessary.
- Keep Apollo client headers on every GraphQL request.
- Never reintroduce `Case_Owner_Alias__c` (removed from schema).
- Always type OwnerId filter variables as `ID!`.
- Keep Mail.app out of the send path; dashboard SMTP is optional.
- `start.sh` / `install.sh` / `update.sh` should keep **`open http://localhost:8090`** after UI is up.

---

*Generated for the SF Notification Center project. For quick start, see [README.md](README.md).*
