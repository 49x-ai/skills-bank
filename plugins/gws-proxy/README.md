# gws-proxy

A Claude Code plugin that lets users share the 49x **gws CLI proxy** OAuth
client to access their own Gmail, Calendar, and Drive through the
[Google Workspace CLI (gws)](https://github.com/googleworkspace/cli) —
without setting up a GCP project, OAuth consent screen, or OAuth client of
their own.

## What it gives you

For each Google account you configure, you end up with:

- `~/.config/gws-<alias>/` — config dir holding the shared `client_secret.json`
  and your encrypted OAuth refresh tokens
- `~/.local/bin/gws-<alias>` — a wrapper that runs `gws` against that config dir
- `/<alias>` — a Claude Code slash command that invokes the wrapper

So if you install with alias `personal` and email `you@gmail.com`, you can run:

```
/personal gmail users messages list --params '{"userId":"me","maxResults":3}'
/personal calendar events list --params '{"calendarId":"primary","maxResults":5}'
/personal drive files list --params '{"pageSize":10}'
```

You can install as many profiles as you want — e.g., `personal`, `work`,
`side` — each backed by a different Google account.

## Installation

```
/plugin install gws-proxy
```

Then add your first account (positional args optional — prompts if missing):

```
/gws-proxy:add-account                          # asks for alias + email
/gws-proxy:add-account personal you@gmail.com   # both upfront
/gws-proxy:add-account personal                 # alias upfront, asks for email
```

It installs the gws CLI if needed, places the bundled OAuth client, opens a
browser for consent, and wires up the slash command. ~2 minutes.

First time? **[Walk through your first account setup →](docs/account-setup.md)**
— what to expect, and which scary-looking warnings are normal.

## Prerequisites

1. **macOS or Linux** with either Homebrew or npm (Node ≥ 18) available so
   gws can be installed. If gws is already installed, neither is required.
2. **`~/.local/bin` on PATH** — the wrapper script lives there. The skill
   warns if it isn't on PATH and tells you exactly which line to add to your
   shell rc.
3. **Your email must be added to IAM** on the `gws-proxy-49x` GCP project as
   `roles/serviceusage.serviceUsageConsumer`. The plugin owner handles this
   out-of-band. If you hit a `403 Caller does not have required permission`
   error during install, message the plugin owner with your email.
4. **Personal Gmail or any Google Workspace account** whose admin permits
   sign-in to unverified third-party apps. Some Workspace admins block this
   — you'll see an `Access blocked: your administrator has disabled
   sign-in...` error if so.

**Not required**: `gcloud`. The OAuth flow runs entirely in the browser. The
skill checks for `gcloud` and reports its presence in the summary, but
nothing in install depends on it.

## How it works

- All profiles share a single Desktop OAuth client published by the
  `gws-proxy-49x` GCP project.
- The OAuth client's `client_secret.json` is embedded in this plugin (Desktop
  OAuth clients are not actually secret — per spec, they can't be).
- When you sign in, **your** Google account's refresh tokens are stored in
  **your** keyring under `~/.config/gws-<alias>/credentials.enc`. The plugin
  owner never sees your tokens or data.
- API calls go directly from your machine to Google with your tokens. The
  `gws-proxy-49x` project only matters for OAuth identity + API quota; it
  has no access to your data.

## What's shared vs. what's yours

| Shared (lives in plugin) | Yours (lives on your machine) |
|---|---|
| OAuth client ID + secret | Refresh tokens (`credentials.enc`) |
| GCP project quota | Your Gmail/Calendar/Drive data |
| Consent screen branding ("gws CLI proxy") | Choice of which account to sign in as |

## Adding more accounts

Just re-run with a different alias:

```
/gws-proxy:add-account
```

Each alias gets its own config dir, wrapper, and slash command. They're
independent — logging out of one doesn't affect the others.

See the [account-setup walkthrough](docs/account-setup.md) for the full
flow and the warnings you'll hit.

## Troubleshooting

See the failure-modes table at the bottom of
[`skills/add-account/SKILL.md`](./skills/add-account/SKILL.md), or the
[account-setup walkthrough](docs/account-setup.md) § *Warnings you'll see*
for the common ones explained in plain terms.

## For the plugin owner

When a new user wants access:

1. Get their email.
2. Add them to IAM:
   ```bash
   gcloud projects add-iam-policy-binding gws-proxy-49x \
     --member="user:<email>" \
     --role="roles/serviceusage.serviceUsageConsumer" \
     --account=49xemailproxy@gmail.com \
     --condition=None
   ```
3. Confirm to them; they can now `/gws-proxy:add-account <alias> <email>`.

The published OAuth consent screen has no test-user list (because it's in
Production mode, unverified), so anyone with the `client_secret.json` plus
the IAM grant can use it.
