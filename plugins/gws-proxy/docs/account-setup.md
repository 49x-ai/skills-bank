# Your first gws account setup

A walkthrough for running `/gws-proxy:add-account` for the first time —
what you'll do, which scary-looking warnings are normal, and what you end
up with.

## What this covers / who it's for

You're about to run `/gws-proxy:add-account` to wire up Gmail, Calendar,
and Drive on the command line. The skill drives almost everything itself,
but the flow includes a browser sign-in step you perform by hand, and
along the way you may see warnings that *look* alarming but are expected.

This doc sets expectations so you can tell a normal prompt from a real
blocker. It's the friendly companion to
[`../skills/add-account/SKILL.md`](../skills/add-account/SKILL.md), which
is the precise implementation spec — read that if you want the exact
mechanics; read this if you just want to know what to expect. The whole
thing takes about two minutes.

## Before you start

You need three things in place:

1. **macOS or Linux, with Homebrew or npm available.** These are only
   needed so the skill can install the gws CLI. If `gws` is already
   installed, you need neither. (npm path needs Node ≥ 18.)
2. **`~/.local/bin` on your PATH.** The per-account wrapper script lives
   there. If it isn't on PATH, the skill won't fail — it just prints the
   exact `export` line for you to add to your shell rc. See
   [PATH warning](#path-warning-localbin-not-on-path) below.
3. **Your email granted IAM access on the `gws-proxy-49x` GCP project.**
   The plugin owner does this out-of-band. If it hasn't happened yet, the
   setup will stop partway with a `403` error — so it's worth pinging the
   plugin owner with your email *first*. See the
   [README "For the plugin owner"](../README.md#for-the-plugin-owner)
   section for what they run.

You also need a Google account — personal Gmail, or a Workspace account
whose admin permits sign-in to unverified third-party apps. Some Workspace
admins block this; see
[Access blocked: administrator](#access-blocked-your-administrator-has-disabled-sign-in)
below.

**You do not need `gcloud`.** The OAuth flow runs entirely in your
browser. The skill checks for `gcloud` only to report whether it's present
— nothing in setup depends on it.

## Running the setup

You kick it off with an alias and the email for the account:

```
/gws-proxy:add-account personal you@gmail.com
```

Both args are optional — leave them off and the skill asks. The alias is
how you'll refer to this account from now on (`personal`, `work`, etc.);
it must be kebab-case and can't be `proxy`.

From there the skill runs the flow itself:

1. **Preflight checks** — looks for `gws`, `brew`/`npm`, your OS,
   `~/.local/bin`, and whether this alias is already configured.
2. **Installs the gws CLI** if it's missing (`brew` on macOS, `npm`
   otherwise).
3. **Places `client_secret.json`** — drops the shared OAuth client into
   `~/.config/gws-<alias>/`.
4. **Browser OAuth consent** — *this is the one step you actively
   perform.* The skill starts the sign-in itself and sends you a Google
   auth URL. You open it in any browser, sign in, and approve scopes —
   then paste one URL back. Details in
   [the next section](#the-sign-in-step-what-you-actually-do).
5. **Verifies the sign-in landed** by fetching your Gmail profile and
   checking the email matches.
6. **Creates the wrapper + slash command** — `~/.local/bin/gws-<alias>`
   and a `/<alias>` Claude Code command.
7. **Smoke test** — runs one call through the wrapper to confirm
   everything works.

When it's done you get a summary listing your account, config dir,
wrapper, and slash command.

## The sign-in step (what you actually do)

This is the only step you perform by hand, and it works even when the
machine running the skill has no browser of its own (a headless box you
reach over chat, say). The skill handles both ends of the OAuth exchange
on that machine — you just supply the browser.

Here's the exchange, start to finish:

1. **The skill sends you a URL.** It has already started the Google
   sign-in in the background and pulled the auth URL out for you.
2. **You open it in any browser** — your laptop, your phone, whatever.
   It does not have to be on the same machine as the skill.
3. **You sign in** as the account you're setting up, click through the
   "Google hasn't verified this app" warning
   ([this is expected](#google-hasnt-verified-this-app)), and approve the
   gmail/calendar/drive scopes.
4. **The browser then fails to load a page** — the address bar shows
   something like `http://localhost:53682/?code=...` and the browser says
   "this site can't be reached." **This is expected and means it
   worked.** That localhost address belongs to a listener on the skill's
   machine, not yours, so your browser can't reach it — but the URL it
   tried to load carries the authorization code.
5. **You copy that whole failed URL** out of the address bar and paste it
   back into the chat.
6. **The skill finishes the exchange** by fetching that URL itself, on
   its machine, where the listener is actually waiting.

The one thing to get right: in step 5, copy the **entire** address-bar
URL, including everything after the `?`. A partial paste won't complete
the sign-in.

## Warnings you'll see (and what they mean)

This is the part worth reading before you start. Most of these look worse
than they are.

### "Google hasn't verified this app"

**Expected. Not a problem.** During the browser sign-in you'll hit a
screen saying Google hasn't verified the app. Click **Advanced**, then
**Go to gws CLI proxy (unsafe)**, then approve the gmail/calendar/drive
scopes.

Why it's safe: the OAuth client is a **Desktop client**, published but
not Google-verified (verification is a process the project owner hasn't
gone through — it doesn't change how the app behaves). When you sign in,
*your* account's refresh tokens are encrypted and stored on *your*
machine under `~/.config/gws-<alias>/`. API calls go straight from your
machine to Google with your tokens — the plugin owner never sees your
tokens or your data. See
[README "How it works"](../README.md#how-it-works) for the full picture.

### PATH warning (`~/.local/bin` not on PATH)

**Easy fix.** If `~/.local/bin` isn't on your PATH, the final report
flags it and gives you the exact line to add — something like:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Paste that into your shell rc (`~/.zshrc` on macOS's default shell,
`~/.bashrc` on most Linux), then restart your terminal. Until you do, the
`gws-<alias>` wrapper won't be found by name — you'd see
`gws-<alias>: command not found`. The slash command still works either
way.

### `403 Caller does not have required permission … gws-proxy-49x`

**Real blocker — but fixable.** This means your email isn't in the
`gws-proxy-49x` IAM allowlist yet. The setup stops here. Send your email
to the plugin owner (jose@49x.ai) and ask them to add you — they run a
one-line `add-iam-policy-binding` command (it's in the
[README](../README.md#for-the-plugin-owner)). Once they confirm, re-run
`/gws-proxy:add-account <alias>` — it picks up where it left off.

### "Access blocked: your administrator has disabled sign-in…"

**Not fixable from your side.** This is your Google Workspace admin's
policy blocking unverified third-party apps. The plugin can't work around
it. Your options: use a personal Google account instead, or ask your
Workspace admin to allowlist the app.

### "This site can't be reached" after approving scopes

**Expected — it means the sign-in worked.** See
[the sign-in step](#the-sign-in-step-what-you-actually-do) above: that
failed-to-load `http://localhost:...` page is the handoff point. Copy the
full URL from the address bar and paste it back.

### Where credentials are stored

The skill stores your OAuth credentials with the gws CLI's **file
keyring backend**, not the OS keyring — that's what lets the flow work on
a headless machine. Your encrypted refresh tokens live in
`~/.config/gws-<alias>/credentials.enc` and the key that decrypts them in
`~/.config/gws-<alias>/.encryption_key`. The wrapper script sets
`GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file` so every `gws-<alias>` call
can read them back; don't delete `.encryption_key` or the credentials
become unrecoverable and you'll need to re-run the skill.

## What you end up with

For the alias `<alias>`, setup leaves you with:

- **`~/.config/gws-<alias>/`** — the config dir, holding the shared
  `client_secret.json`, your encrypted OAuth refresh tokens
  (`credentials.enc`), and the file-backend key that decrypts them
  (`.encryption_key`).
- **`~/.local/bin/gws-<alias>`** — a small wrapper script that runs `gws`
  pointed at that config dir.
- **`~/.claude/commands/<alias>.md`** — a Claude Code slash command,
  `/<alias>`, that calls the wrapper.

Each alias is fully self-contained — different aliases use different
config dirs and don't affect each other.

## Using your alias from now on

Once setup is done, drive your account through the `/<alias>` slash
command in any Claude Code session:

```
/<alias> gmail users messages list --params '{"userId":"me","maxResults":3}'
/<alias> calendar events list --params '{"calendarId":"primary","maxResults":5}'
/<alias> drive files list --params '{"pageSize":10}'
```

The wrapper also works directly in any shell, no Claude needed:

```
gws-<alias> gmail users getProfile --params '{"userId":"me"}'
```

To **add another account**, re-run `/gws-proxy:add-account` with a new
alias. Each profile is independent — signing out of one doesn't touch the
others.

## If something breaks

Re-running `/gws-proxy:add-account <alias>` is safe — every step checks
before acting, and it asks before overwriting anything. A healthy alias
just gets re-verified; a broken one gets repaired.

For the full symptom-to-fix list — including auth sessions that don't
survive a restart and other edge cases — see the **Failure modes** table
at the bottom of
[`../skills/add-account/SKILL.md`](../skills/add-account/SKILL.md).
