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
  gws gmail users getProfile --params '{"userId":"me"}'
```

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

## Step 5 — Run OAuth consent (user runs this in their terminal)

`gws auth login` opens a browser and waits on a localhost callback. The
**user must run it from their terminal** (the `!` prefix in the prompt sends
output back to this session). Tell them to paste:

```
! GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$HOME/.config/gws-<alias>" gws auth login -s gmail,calendar,drive
```

Substitute the real alias.

Expected browser flow:
1. URL prints; the browser auto-opens or they click the link.
2. Sign in as **the email from step 1** (this is what gets stored).
3. "Google hasn't verified this app" warning appears — **Advanced → Go to
   gws CLI proxy (unsafe)**. The app is published but not Google-verified;
   safe for internal use.
4. Approve gmail/calendar/drive scopes.
5. Terminal prints `"status": "success"`.

If they hit `Access blocked: your administrator has disabled sign-in...` —
their Workspace admin blocks unverified third-party apps. No plugin-side fix;
they need their admin or a different account.

Wait for the user's reply with the output before continuing.

## Step 6 — Verify auth landed

```bash
env GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$HOME/.config/gws-$ALIAS" \
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
exec env GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$HOME/.config/gws-<alias>" gws "$@"
```

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
| `gws auth status` shows no session after restart | OS keyring may have been reset. Re-run step 5. |
| Headless / keyring locked | `export GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file` then redo step 5. Credentials then live at `~/.config/gws-<alias>/.encryption_key`. |

## Idempotency

- Re-running with the same alias is a no-op when the alias is healthy.
- Backups use `.bak.YYYYMMDD` suffixes. Don't delete without asking.
- Never run `gws auth logout` as part of this skill.
