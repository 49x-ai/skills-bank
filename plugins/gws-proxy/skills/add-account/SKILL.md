---
name: add-account
description: Add a gws-<alias> CLI profile that uses the shared 49x gws CLI proxy OAuth client. Accepts positional args `<alias> <email>`. Installs the gws CLI if missing, drops the bundled client_secret.json into ~/.config/gws-<alias>/, runs OAuth consent, and creates the gws-<alias> wrapper plus /<alias> slash command. Use when the user says "add a Google account", "add gws account", "set up gws", "install gws", "configure gmail CLI", "I want /work or /personal", or invokes `/gws-proxy:add-account`.
user-invocable: true
model: haiku
allowed-tools:
  - Read
  - Write
  - Edit
  - AskUserQuestion
  - Bash(ls *)
  - Bash(mkdir *)
  - Bash(chmod *)
  - Bash(cp *)
  - Bash(mv *)
  - Bash(rm *)
  - Bash(test *)
  - Bash(cat *)
  - Bash(command *)
  - Bash(which *)
  - Bash(brew *)
  - Bash(npm *)
  - Bash(node *)
  - Bash(gws *)
  - Bash(gws-*)
  - Bash(gcloud *)
  - Bash(echo *)
  - Bash(date *)
  - Bash(grep *)
  - Bash(env *)
  - Bash(uname *)
  - Bash(printenv *)
  - Bash(curl *)
  - Bash(sleep *)
  - Bash(nohup *)
  - Bash(tail *)
  - Bash(kill *)
---

# /gws-proxy:add-account — add a gws profile

Stand up a `gws-<alias>` profile that shares the 49x gws CLI proxy OAuth
client. End result: a `/<alias>` slash command that runs gws against the
user's Google account, with no Cloud Console clicks.

Resumable — every step checks before acting. Re-running with the same alias
is a no-op (or surfaces what's wrong).

## Invocation

```
/gws-proxy:add-account <alias> <email>
```

Both args are optional; missing ones are prompted for in step 1.

## What the user needs in place

1. **macOS or Linux** with `brew` or `npm` (Node ≥ 18) available — only needed
   if `gws` isn't already installed.
2. **`~/.local/bin` on PATH** — the wrapper script lives there. Skill warns
   if it isn't on PATH; doesn't auto-fix shell rc.
3. **Their email pre-authorized in IAM** on the `gws-proxy-49x` GCP project as
   `roles/serviceusage.serviceUsageConsumer`. Plugin owner does this
   out-of-band. The smoke test in step 7 will surface a missing IAM grant
   with a `Caller does not have required permission to use project
   gws-proxy-49x` error.

Note: `gcloud` is **not** required for end users. The OAuth flow happens in
the browser. The skill checks for `gcloud` only to report it as available,
which can be useful later if the user wants to manage GCP themselves.

## Step 1 — Parse / collect inputs

The user may have invoked with positional args:

- `/gws-proxy:add-account personal joe@x.com` → `ALIAS=personal`, `EMAIL=joe@x.com`
- `/gws-proxy:add-account personal` → `ALIAS=personal`, prompt for EMAIL
- `/gws-proxy:add-account` → prompt for both

Validation:
- **ALIAS** must match `^[a-z][a-z0-9-]*$` (kebab-case, starts with letter).
  Reject `proxy` because it conflicts with the project owner's account; suggest
  `personal`, `work`, or `<purpose>`.
- **EMAIL** must contain `@` and a `.` in the domain. No real schema check —
  the OAuth flow validates it for real.

Missing args → single `AskUserQuestion` with both prompts. Recommend
`personal` or `work` as alias options if neither is taken yet (check
`~/.config/gws-personal/` and `~/.config/gws-work/` existence).

Cache as `ALIAS` and `EMAIL` for the rest of the steps.

## Step 2 — Preflight

Run these checks in parallel and collect results:

```bash
command -v gws
command -v brew
command -v npm && node -v 2>/dev/null
command -v gcloud
uname -s                                # Darwin | Linux | other
test -d "$HOME/.local/bin"
echo "$PATH" | grep -q "$HOME/.local/bin" && echo "on_path" || echo "not_on_path"
test -d "$HOME/.config/gws-$ALIAS"
test -f "$HOME/.config/gws-$ALIAS/credentials.enc"
```

Classify each result:

| Check | Required? | Action if missing |
|---|---|---|
| `gws` | Yes (or installable) | Continue to step 3 to install |
| `brew` or `npm` | Only if gws missing | If both missing AND gws missing → stop, tell user to install gws manually from https://github.com/googleworkspace/cli/releases |
| `node -v ≥ 18` | Only if using npm path | If <18 and brew unavailable → stop |
| `gcloud` | No (informational) | Note as missing in summary; don't block |
| OS = Darwin or Linux | Yes | If other → stop, surface the OS name |
| `~/.local/bin` exists | Yes | Create it via `mkdir -p` |
| `~/.local/bin` on PATH | Recommended | Warn in final report with exact rc line to add |
| `~/.config/gws-$ALIAS/` exists | — | If yes AND `credentials.enc` exists → step 2a |

### Step 2a — Alias already configured?

If both the config dir AND `credentials.enc` exist for this alias, run:

```bash
env GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$HOME/.config/gws-$ALIAS" \
  GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file \
  gws gmail users getProfile --params '{"userId":"me"}'
```

The `KEYRING_BACKEND=file` env var is required: this skill stores
credentials with the file backend (see step 5), and they're unreadable
without it.

- If success AND `emailAddress` matches `$EMAIL` → already configured;
  jump to step 8 (re-create wrapper + slash command idempotently in case
  they were deleted, then exit).
- If success but email differs → ask the user whether to **overwrite** the
  alias or pick a different one.
- If error → continue; step 5 will re-auth.

## Step 3 — Install gws CLI (only if missing)

Pick the first method whose tool is available:

```bash
brew install googleworkspace-cli           # macOS preferred
npm install -g @googleworkspace/cli        # Linux / fallback, needs Node ≥ 18
```

Verify `gws --version` prints a version. If it doesn't, surface the install
error verbatim and stop.

## Step 4 — Place client_secret.json

The bundled OAuth client lives at:
```
${CLAUDE_PLUGIN_ROOT}/skills/add-account/references/client_secret.json
```

```bash
mkdir -p "$HOME/.config/gws-$ALIAS"
# Back up any pre-existing client_secret before overwriting
test -f "$HOME/.config/gws-$ALIAS/client_secret.json" && \
  cp "$HOME/.config/gws-$ALIAS/client_secret.json" \
     "$HOME/.config/gws-$ALIAS/client_secret.json.bak.$(date +%Y%m%d)"
cp "${CLAUDE_PLUGIN_ROOT}/skills/add-account/references/client_secret.json" \
   "$HOME/.config/gws-$ALIAS/client_secret.json"
```

## Step 5 — Run OAuth consent (headless, skill-driven)

`gws auth login` opens a browser and waits on a localhost callback. On a
headless box reached only over chat, there's no browser and no way to land
that callback locally. So the skill drives the whole exchange **on the box**
and only hands the human-browser step to the user. No SSH, no
port-forwarding.

The listener (started in 5a) and the `curl` that completes it (5c) both run
on the box; only the sign-in (5b) happens in the user's own browser.

### Step 5a — Start the login listener in the background

```bash
LOG="$HOME/.config/gws-$ALIAS/auth.log"
rm -f "$LOG"
nohup env GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$HOME/.config/gws-$ALIAS" \
  GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file \
  gws auth login -s gmail,calendar,drive >"$LOG" 2>&1 &
echo "AUTH_PID=$!"
```

`KEYRING_BACKEND=file` is required — the OS keyring isn't available
headless. Credentials land at `~/.config/gws-<alias>/.encryption_key` +
`credentials.enc`. Cache `AUTH_PID` so you can `kill` it later if it hangs.

### Step 5b — Send the user the auth URL

Poll the log until the Google auth URL appears:

```bash
for i in $(seq 1 30); do
  grep -om1 'https://accounts.google.com/[^[:space:]]*' "$LOG" && break
  sleep 1
done
```

If no URL shows up within ~30s, `cat "$LOG"` and surface the contents — the
login process likely failed to start. Otherwise send the URL to the user
with these instructions:

1. Open the URL in **any browser** — laptop or phone, doesn't have to be the
   box.
2. Sign in as **the email from step 1** (this is what gets stored).
3. "Google hasn't verified this app" warning appears — **Advanced → Go to
   gws CLI proxy (unsafe)**. The app is published but not Google-verified;
   safe for internal use.
4. Approve gmail/calendar/drive scopes.
5. The browser then tries to load `http://localhost:<port>/?code=...` and
   **fails to connect** — "this site can't be reached" is *expected*, the
   listener is on the box, not their machine.
6. They copy the **full URL from the address bar** (the whole
   `http://localhost:...` string, including `?code=...`) and paste it back
   into this chat.

If they hit `Access blocked: your administrator has disabled sign-in...` —
their Workspace admin blocks unverified third-party apps. No plugin-side fix;
they need their admin or a different account.

Wait for the user to paste the localhost URL before continuing.

### Step 5c — Complete the token exchange on the box

`curl` the pasted URL on the box — it hits the still-waiting listener from
5a and completes the OAuth token exchange:

```bash
curl -s "<the-localhost-url-the-user-pasted>"
```

Quote the URL exactly as pasted. The `code` and `state` params must arrive
intact.

### Step 5d — Verify the exchange landed

```bash
grep -q '"status": "success"' "$LOG" && echo "AUTH_OK" || cat "$LOG"
```

- `AUTH_OK` → the background process exits on its own; move to step 6.
- No success line → surface the log. Common causes: the user pasted a stale
  or partial URL, or signed in as the wrong account. If the listener is
  still running, `kill "$AUTH_PID"` and restart from 5a.

## Step 6 — Verify auth landed

```bash
env GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$HOME/.config/gws-$ALIAS" \
  GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file \
  gws gmail users getProfile --params '{"userId":"me"}'
```

Check the JSON:
- **`emailAddress` matches `$EMAIL`** → continue.
- **`emailAddress` differs** → they signed in as the wrong account; offer
  to redo step 5.
- **HTTP 403 `Caller does not have required permission to use project
  gws-proxy-49x`** → IAM grant missing. Stop and tell the user verbatim:
  *"Your email isn't in the gws-proxy-49x IAM allowlist yet. Send your email
  to the plugin owner (jose@49x.ai) and ask them to run the
  `add-iam-policy-binding` command from the plugin README; then re-run
  this skill."*
- **Any other error** → surface it verbatim.

## Step 7 — Create wrapper script

Write `~/.local/bin/gws-<alias>` (substitute real alias):

```bash
#!/usr/bin/env bash
exec env GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$HOME/.config/gws-<alias>" \
  GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file \
  gws "$@"
```

`KEYRING_BACKEND=file` must match what step 5 used to store the
credentials — without it the wrapper can't read them back.

```bash
chmod +x "$HOME/.local/bin/gws-$ALIAS"
```

## Step 8 — Create slash command

Write `~/.claude/commands/<alias>.md` (substitute `<alias>` and `<email>`):

```markdown
---
description: Run a gws command against the <email> Google account
argument-hint: <gws args, e.g. "calendar events list --params '{\"calendarId\":\"primary\"}'">
---
!`gws-<alias> $ARGUMENTS`
```

If the file exists, ask before overwriting.

## Step 9 — Final smoke test via the wrapper

```bash
gws-$ALIAS gmail users getProfile --params '{"userId":"me"}'
```

`emailAddress` should still match `$EMAIL`. If not, surface the discrepancy.

## Step 10 — Report

Single message to the user, including any warnings captured in step 2:

```
✅ gws-<alias> profile installed.
   Account:   <email>
   Config:    ~/.config/gws-<alias>/
   Wrapper:   ~/.local/bin/gws-<alias>
   Slash cmd: /<alias>

Detected:
   gws:      <version>
   gcloud:   <version OR "not installed (optional)">
   ~/.local/bin on PATH: <yes | NO — add `export PATH="$HOME/.local/bin:$PATH"` to your ~/.zshrc>

Try it:
   /<alias> gmail users messages list --params '{"userId":"me","maxResults":3}'

Add another account: /gws-proxy:add-account <other-alias> <other-email>
```

## Failure modes — quick remediation

| Symptom | Fix |
|---|---|
| `Access blocked: Google hasn't verified this app` | Re-run step 5; click **Advanced → Go to gws CLI proxy (unsafe)**. |
| `Access blocked: your administrator has disabled sign-in...` | Workspace policy blocks unverified apps. Admin allowlist or use a personal account. |
| `Caller does not have required permission to use project gws-proxy-49x` | IAM grant missing. User pings plugin owner; owner runs `gcloud projects add-iam-policy-binding gws-proxy-49x --member="user:<email>" --role="roles/serviceusage.serviceUsageConsumer" --account=49xemailproxy@gmail.com --condition=None`. |
| `gws-<alias>: command not found` | `~/.local/bin` not on PATH. `export PATH="$HOME/.local/bin:$PATH"` in shell rc, restart terminal. |
| `gws auth status` shows no session after restart | Re-run the skill — step 5 re-auths. The file-backend key lives at `~/.config/gws-<alias>/.encryption_key`; if that file was deleted, the stored credentials can't be decrypted. |
| No auth URL in `auth.log` within ~30s (step 5b) | The background `gws auth login` failed to start. `cat` the log; usual cause is a missing/malformed `client_secret.json` — redo step 4, then 5a. |
| Browser shows "this site can't be reached" after approving scopes | **Expected** — the localhost listener is on the box, not the user's machine. They copy the full `http://localhost:...?code=...` URL from the address bar and paste it back; step 5c curls it on the box. |
| `curl` of the pasted URL returns nothing and no `"status": "success"` lands | Stale or partial URL, or the listener already exited. `kill "$AUTH_PID"` if still running and restart from 5a; make sure the user pastes the **entire** address-bar URL. |
| Credentials unreadable / keyring error when running the wrapper | The wrapper or a verify command is missing `GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file`. Step 5 stores creds with the file backend, so every read needs that env var — check step 7's wrapper. |

## Idempotency

- Re-running with the same alias is a no-op when the alias is healthy.
- Backups use `.bak.YYYYMMDD` suffixes. Don't delete without asking.
- Never run `gws auth logout` as part of this skill.
