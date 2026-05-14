# Default settings for the Telegram channel

Step 5a of `setup/SKILL.md` and `connect/SKILL.md` writes three
defaults to `~/.claude/settings.json` so the bot is friction-free
once the user relaunches with `--channels`:

1. `env.MCP_TIMEOUT = "60000"` — gives MCP servers a 60-second
   startup window. The default is shorter, and on a cold cache the
   `bun install` that backs the Telegram MCP server can miss it,
   leaving the channel marked unhealthy.
2. `permissions.allow` entry `mcp__plugin_telegram_telegram__*` —
   pre-approves all Telegram MCP tools (`reply`, `react`,
   `edit_message`, `download_attachment`) so chatting with the bot
   doesn't trigger a permission prompt on every message.
3. A scoped set of `permissions.allow` `Bash(...)` entries for the
   speech-to-text flow — the chief-of-staff agent transcribes inbound
   Telegram voice notes itself (detect / install / transcribe an STT
   CLI), and a headless bot can't answer permission prompts. The
   entries are kept narrow (specific package and tool names, not a
   broad `Bash(pip3 install *)`).

Both writes are idempotent and non-destructive: this file is also
the "I ran it twice" path. The merge never deletes other keys, never
clobbers a stricter user setting, and prints back exactly what was
changed.

## Scope: user-global, not project-local

Write `~/.claude/settings.json`, **not** any project's
`.claude/settings.json` or `.claude/settings.local.json`. The
Telegram channel runs across all sessions on the machine, so the
allow rule and MCP timeout need to take effect everywhere — not
just in the directory where the install ran. This matches how
`/telegram:configure` already writes user-global state to
`~/.claude/channels/telegram/.env`.

## Procedure

1. **Read** `~/.claude/settings.json` with the Read tool. Treat a
   missing file as the empty object `{}` and use Write at the end
   instead of Edit. If the file exists but is empty, also treat as
   `{}`.

2. **MCP_TIMEOUT decision.** Look at `env.MCP_TIMEOUT`:
   - Absent → set to `"60000"`.
   - Present and parses as a number `< 60000` → overwrite to
     `"60000"`.
   - Present and parses as a number `>= 60000` → leave alone (the
     user already picked a longer window; don't shrink it).
   - Present and not numeric → leave alone (don't second-guess a
     custom value); note in the user-facing message.

3. **Allow rule decision.** Look at `permissions.allow` (treat
   missing `permissions` or `permissions.allow` as `[]`):
   - Already contains `"mcp__plugin_telegram_telegram__*"` → no
     change.
   - Already contains a broader entry that subsumes it (e.g.
     `"mcp__*"` or `"mcp__plugin_telegram_telegram"` without the
     trailing `__*` but with a wildcard that covers it — be
     conservative: only treat exact `"mcp__*"` as broader) → no
     change.
   - Otherwise → append `"mcp__plugin_telegram_telegram__*"` to the
     end of the array, preserving existing entries and order.

4. **STT Bash rules decision.** The speech-to-text flow needs these
   scoped `permissions.allow` entries:

   ```
   Bash(command *)
   Bash(uname *)
   Bash(whisper-ctranslate2 *)
   Bash(whisper *)
   Bash(whisper-cli *)
   Bash(whisper-cpp *)
   Bash(mlx_whisper *)
   Bash(brew install whisper-cpp)
   Bash(pipx install whisper-ctranslate2)
   Bash(pip3 install --user whisper-ctranslate2)
   Bash(pip3 install --user mlx-whisper)
   ```

   For each entry, look at `permissions.allow` (same `[]` fallback as
   step 3):
   - Already present verbatim → skip it.
   - Already covered by a broader entry the user set (e.g. `Bash(*)`,
     or `Bash(pip3 install *)` covering the `pip3` entries) → skip it.
     Be conservative — only skip on a clearly broader wildcard.
   - Otherwise → append it to the end of the array, preserving
     existing entries and order.

   Append only the missing ones; a re-run adds nothing.

5. **Write back.** Preserve every other key (other env vars,
   `permissions.deny`, `permissions.ask`, `hooks`, `model`,
   anything else) byte-for-byte where possible. Pretty-print with
   2-space indent and a trailing newline to match the conventional
   style.
   - If the file existed: use Edit with surrounding context to
     replace just the affected sub-objects (e.g. the whole `env`
     block, the whole `permissions.allow` array). This minimizes
     diff churn.
   - If the file did not exist: use Write with a fresh JSON object
     containing only the three defaults.

6. **Print to the user verbatim**, substituting actuals based on
   what changed:

   > Wrote default settings to `~/.claude/settings.json`:
   > - `env.MCP_TIMEOUT = "60000"` — 60s MCP startup timeout (room
   >   for a cold-cache `bun install`)
   > - `permissions.allow += "mcp__plugin_telegram_telegram__*"` —
   >   auto-approves Telegram tools so chatting with the bot doesn't
   >   prompt
   > - `permissions.allow += <N>` scoped `Bash(...)` STT rules —
   >   lets the bot detect, install, and run a speech-to-text CLI to
   >   transcribe voice notes without a permission prompt
   >
   > These take effect on the next session. Anything already set (or
   > already broader) was left untouched.

   If one or both were already in place, replace the corresponding
   bullet with `already set, left untouched` and the actual current
   value, e.g. *`env.MCP_TIMEOUT` already `"120000"`, left
   untouched`*. The user should always be able to read this output
   and know exactly what state their settings file is in.

## What this procedure does NOT do

- Writes only the scoped STT `Bash(...)` allow rules listed in step 4
  (specific tool and package names) and the Telegram MCP wildcard — no
  broad `Bash(*)` rule, and no other allow rules of any kind.
- Does not touch project `.claude/settings.json` or
  `.claude/settings.local.json`.
- Does not remove anything on a re-run or on uninstall — additions
  only. The user can delete the entries by hand if they want.
- Does not gate behind `AskUserQuestion`. The install flow itself
  is the consent; the verbatim user-facing print is the audit
  trail.
