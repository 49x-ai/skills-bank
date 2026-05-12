#!/usr/bin/env python3
"""pty-drive.py — drive an interactive `claude` process under a pty.

Why this exists: `claude -p` doesn't render `AskUserQuestion`. Skills
that need user input (install-recipes customize, demo's "fire?" prompt,
connect's pairing flow) only run in interactive mode. We need a way to
script those answers from the harness.

Approach: spawn `claude` (no `-p`) under a pseudo-tty, watch the stdout
stream for known prompt strings, send the canned answer for each. The
answers come from a JSON config:

    {
      "initial_prompt": "/cos-bot:install-recipes",
      "answers": [
        {"match": "Quickest path is", "send": "1\\r"},
        {"match": "VIPs", "send": "joseroca@gmail.com\\r"},
        {"match": "Recipe install complete", "send": "/exit\\r"}
      ],
      "timeout_per_match": 60,
      "overall_timeout": 300
    }

The matcher is plain-string (case-insensitive). Order matters — once a
match fires, the driver advances to the next answer. If a match never
arrives within `timeout_per_match`, the driver dumps the buffer and
exits non-zero. The whole run is bounded by `overall_timeout`.

Output:
- stdout: live mirror of the pty (so callers can `tee`)
- exit code: 0 on success, 1 on timeout, 2 on bad config

Usage:
    pty-drive.py --config <answers.json> --output <pty.log> -- claude --plugin-dir ...
"""

from __future__ import annotations

import argparse
import errno
import json
import os
import pty
import select
import signal
import sys
import time
from pathlib import Path


def _strip_ansi(s: str) -> str:
    # Cheap ANSI-escape stripper; good enough for substring matching against
    # claude's TUI. We don't try to interpret the escapes, just remove them.
    out = []
    i = 0
    while i < len(s):
        if s[i] == "\x1b":
            # Skip CSI / other escape sequences until alpha or stop char.
            j = i + 1
            if j < len(s) and s[j] == "[":
                j += 1
                while j < len(s) and not (0x40 <= ord(s[j]) <= 0x7E):
                    j += 1
                i = j + 1
            else:
                i = j + 1  # ESC + one char
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--config", required=True, help="path to canned-answers JSON")
    p.add_argument("--output", required=True, help="path for full pty transcript")
    p.add_argument("argv", nargs=argparse.REMAINDER, help="-- <command> [args...]")
    args = p.parse_args()

    if not args.argv or args.argv[0] != "--":
        print("error: pass the target command after --", file=sys.stderr)
        return 2
    cmd = args.argv[1:]

    try:
        config = json.loads(Path(args.config).read_text())
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"error reading config: {e}", file=sys.stderr)
        return 2

    initial = config.get("initial_prompt", "")
    answers = list(config.get("answers", []))
    overall = float(config.get("overall_timeout", 300))
    per_match = float(config.get("timeout_per_match", 60))

    transcript = open(args.output, "wb")

    pid, fd = pty.fork()
    if pid == 0:  # child
        os.execvp(cmd[0], cmd)
        os._exit(127)

    # Parent — drive the pty.
    buf = ""
    started = time.time()
    last_match = started
    next_idx = 0
    sent_initial = False

    def send(text: str) -> None:
        os.write(fd, text.encode())

    try:
        while True:
            now = time.time()
            if now - started > overall:
                print(f"\n[pty-drive] overall timeout {overall}s exceeded", file=sys.stderr)
                return 1

            if next_idx < len(answers) and now - last_match > per_match:
                target = answers[next_idx].get("match", "<?>")
                print(f"\n[pty-drive] timeout waiting for: {target!r}", file=sys.stderr)
                print(f"[pty-drive] last 800 chars of buffer:\n{buf[-800:]!r}", file=sys.stderr)
                return 1

            # Send the initial prompt once the child looks ready.
            # Heuristic: any text on the pty == ready. claude prints its
            # banner before accepting input.
            if initial and not sent_initial and len(buf) > 50:
                send(initial + "\r")
                sent_initial = True

            try:
                r, _, _ = select.select([fd], [], [], 0.2)
            except (OSError, ValueError):
                break

            if fd in r:
                try:
                    chunk = os.read(fd, 4096)
                except OSError as e:
                    if e.errno == errno.EIO:
                        break
                    raise
                if not chunk:
                    break
                transcript.write(chunk)
                transcript.flush()
                # Mirror to stdout so a human watching `tee` can see progress.
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()

                buf += _strip_ansi(chunk.decode("utf-8", errors="replace"))
                # Cap the matching buffer; only the last 8k matters.
                if len(buf) > 16384:
                    buf = buf[-8192:]

                while next_idx < len(answers):
                    target = answers[next_idx]["match"]
                    if target.lower() in buf.lower():
                        send_str = answers[next_idx]["send"]
                        send(send_str)
                        last_match = time.time()
                        next_idx += 1
                        # Reset buf to avoid re-matching the same trigger.
                        buf = ""
                    else:
                        break

            # Child exited?
            try:
                pid_done, status = os.waitpid(pid, os.WNOHANG)
            except ChildProcessError:
                break
            if pid_done == pid:
                exit_status = os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1
                if next_idx < len(answers):
                    print(
                        f"\n[pty-drive] child exited with {exit_status} but "
                        f"{len(answers) - next_idx} answers still pending",
                        file=sys.stderr,
                    )
                    return 1
                return exit_status

    finally:
        try:
            os.close(fd)
        except OSError:
            pass
        transcript.close()
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
