#!/usr/bin/env python3
"""perf.py — parse a session JSONL and emit token / cost / latency reports.

Usage:
    perf.py parse <report-dir>          # → perf.json + report.md inside the dir
    perf.py compare <run-a> <run-b>     # → comparison.md printed to stdout

`session.jsonl` is the per-session timeline Claude writes to
~/.claude/projects/<slug>/<sessionId>.jsonl. Each line is a JSON object.
We care about lines with type=="assistant" and a `message.usage` block,
plus `timestamp` for latency.

The price table below is dated; bump as Anthropic updates pricing.
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path
from typing import Iterable

# USD per 1M tokens. Inline + dated; update as pricing changes.
# Source: https://www.anthropic.com/pricing (as of 2026-05).
PRICES_USD_PER_MTOK = {
    # Opus 4.7 — anchor; the model in claude-opus-4-7[1m]
    "claude-opus-4-7": {
        "input": 15.00,
        "output": 75.00,
        "cache_read": 1.50,
        "cache_creation": 18.75,
    },
    # Sonnet 4.6
    "claude-sonnet-4-6": {
        "input": 3.00,
        "output": 15.00,
        "cache_read": 0.30,
        "cache_creation": 3.75,
    },
    # Haiku 4.5
    "claude-haiku-4-5": {
        "input": 1.00,
        "output": 5.00,
        "cache_read": 0.10,
        "cache_creation": 1.25,
    },
}


def _price_key(model_id: str) -> str | None:
    """Map a full model id (claude-haiku-4-5-20251001) to a price key."""
    for key in PRICES_USD_PER_MTOK:
        if model_id.startswith(key):
            return key
    return None


@dataclass
class Turn:
    index: int
    timestamp: str
    model: str
    input_tokens: int
    output_tokens: int
    cache_read_tokens: int
    cache_creation_tokens: int
    latency_ms: int | None
    cost_usd: float


@dataclass
class RunPerf:
    run_id: str
    turn_count: int
    wall_clock_ms: int
    total_input: int = 0
    total_output: int = 0
    total_cache_read: int = 0
    total_cache_creation: int = 0
    total_cost_usd: float = 0.0
    sdk_total_cost_usd: float | None = None  # from run.json if present
    by_model: dict = field(default_factory=dict)
    turns: list[Turn] = field(default_factory=list)

    def to_dict(self) -> dict:
        d = asdict(self)
        d["turns"] = [asdict(t) for t in self.turns]
        return d


def _turn_cost(model_id: str, usage: dict) -> float:
    key = _price_key(model_id)
    if not key:
        return 0.0
    p = PRICES_USD_PER_MTOK[key]
    return (
        usage.get("input_tokens", 0) * p["input"]
        + usage.get("output_tokens", 0) * p["output"]
        + usage.get("cache_read_input_tokens", 0) * p["cache_read"]
        + usage.get("cache_creation_input_tokens", 0) * p["cache_creation"]
    ) / 1_000_000


def _parse_ts(ts: str) -> datetime | None:
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None


def parse_jsonl(path: Path) -> list[dict]:
    rows = []
    with path.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return rows


def build_run_perf(run_id: str, rows: Iterable[dict]) -> RunPerf:
    rows = list(rows)
    turns: list[Turn] = []
    prev_ts: datetime | None = None
    first_ts: datetime | None = None
    last_ts: datetime | None = None

    for i, row in enumerate(rows):
        if row.get("type") != "assistant":
            continue
        msg = row.get("message", {})
        usage = msg.get("usage") or {}
        if not usage:
            continue
        ts = _parse_ts(row.get("timestamp", ""))
        if ts:
            first_ts = first_ts or ts
            last_ts = ts
        latency_ms = None
        if ts and prev_ts:
            latency_ms = int((ts - prev_ts).total_seconds() * 1000)
        prev_ts = ts

        model = msg.get("model", "unknown")
        cost = _turn_cost(model, usage)
        turns.append(
            Turn(
                index=len(turns),
                timestamp=row.get("timestamp", ""),
                model=model,
                input_tokens=usage.get("input_tokens", 0),
                output_tokens=usage.get("output_tokens", 0),
                cache_read_tokens=usage.get("cache_read_input_tokens", 0),
                cache_creation_tokens=usage.get("cache_creation_input_tokens", 0),
                latency_ms=latency_ms,
                cost_usd=cost,
            )
        )

    perf = RunPerf(
        run_id=run_id,
        turn_count=len(turns),
        wall_clock_ms=int((last_ts - first_ts).total_seconds() * 1000)
        if first_ts and last_ts
        else 0,
        turns=turns,
    )
    for t in turns:
        perf.total_input += t.input_tokens
        perf.total_output += t.output_tokens
        perf.total_cache_read += t.cache_read_tokens
        perf.total_cache_creation += t.cache_creation_tokens
        perf.total_cost_usd += t.cost_usd
        bucket = perf.by_model.setdefault(
            t.model,
            {
                "turns": 0,
                "input": 0,
                "output": 0,
                "cache_read": 0,
                "cache_creation": 0,
                "cost_usd": 0.0,
            },
        )
        bucket["turns"] += 1
        bucket["input"] += t.input_tokens
        bucket["output"] += t.output_tokens
        bucket["cache_read"] += t.cache_read_tokens
        bucket["cache_creation"] += t.cache_creation_tokens
        bucket["cost_usd"] += t.cost_usd

    return perf


def render_report_md(perf: RunPerf) -> str:
    lines = [f"# perf report — {perf.run_id}", ""]
    lines.append(f"- turns: {perf.turn_count}")
    lines.append(f"- wall clock: {perf.wall_clock_ms / 1000:.1f}s")
    lines.append(f"- total cost (table-priced): ${perf.total_cost_usd:.4f}")
    if perf.sdk_total_cost_usd is not None:
        lines.append(f"- total cost (SDK reported): ${perf.sdk_total_cost_usd:.4f}")
    lines.append("")
    lines.append("## by model")
    lines.append("")
    lines.append("| model | turns | input | output | cache_read | cache_creation | cost |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|")
    for model, b in sorted(perf.by_model.items()):
        lines.append(
            f"| `{model}` | {b['turns']} | {b['input']} | {b['output']} | "
            f"{b['cache_read']} | {b['cache_creation']} | ${b['cost_usd']:.4f} |"
        )
    lines.append("")
    lines.append("## per turn")
    lines.append("")
    lines.append("| # | model | input | output | cache_read | cache_creation | latency | cost |")
    lines.append("|---:|---|---:|---:|---:|---:|---:|---:|")
    for t in perf.turns:
        lat = f"{t.latency_ms}ms" if t.latency_ms is not None else "—"
        lines.append(
            f"| {t.index} | `{t.model}` | {t.input_tokens} | {t.output_tokens} | "
            f"{t.cache_read_tokens} | {t.cache_creation_tokens} | {lat} | "
            f"${t.cost_usd:.4f} |"
        )
    return "\n".join(lines) + "\n"


def cmd_parse(report_dir: Path) -> int:
    jsonl = report_dir / "session.jsonl"
    if not jsonl.exists():
        print(f"error: {jsonl} not found", file=sys.stderr)
        return 1
    perf = build_run_perf(report_dir.name, parse_jsonl(jsonl))

    run_json = report_dir / "run.json"
    if run_json.exists():
        try:
            data = json.loads(run_json.read_text())
            if isinstance(data, dict) and "total_cost_usd" in data:
                perf.sdk_total_cost_usd = float(data["total_cost_usd"])
        except (json.JSONDecodeError, ValueError):
            pass

    (report_dir / "perf.json").write_text(json.dumps(perf.to_dict(), indent=2))
    (report_dir / "report.md").write_text(render_report_md(perf))
    print(f"[perf] wrote {report_dir / 'perf.json'}")
    print(f"[perf] wrote {report_dir / 'report.md'}")
    return 0


def cmd_compare(a: Path, b: Path) -> int:
    pa = json.loads((a / "perf.json").read_text())
    pb = json.loads((b / "perf.json").read_text())

    def fmt(label, va, vb, fmt_str="{:.4f}", suffix=""):
        delta = vb - va
        sign = "+" if delta >= 0 else ""
        pct = ""
        if va:
            pct = f" ({sign}{(delta / va) * 100:.1f}%)"
        return f"- {label}: {fmt_str.format(va)}{suffix} → {fmt_str.format(vb)}{suffix}{pct}"

    out = [
        f"# comparison — {a.name} → {b.name}",
        "",
        fmt("total cost (table)", pa["total_cost_usd"], pb["total_cost_usd"], "${:.4f}"),
    ]
    if pa.get("sdk_total_cost_usd") is not None and pb.get("sdk_total_cost_usd") is not None:
        out.append(fmt("total cost (SDK)", pa["sdk_total_cost_usd"], pb["sdk_total_cost_usd"], "${:.4f}"))
    out.append(fmt("turn count", pa["turn_count"], pb["turn_count"], "{}"))
    out.append(fmt("wall clock", pa["wall_clock_ms"] / 1000, pb["wall_clock_ms"] / 1000, "{:.1f}", "s"))
    out.append(fmt("input tokens", pa["total_input"], pb["total_input"], "{}"))
    out.append(fmt("output tokens", pa["total_output"], pb["total_output"], "{}"))
    out.append("")
    out.append("## models seen")
    out.append(f"- {a.name}: {sorted(pa['by_model'].keys())}")
    out.append(f"- {b.name}: {sorted(pb['by_model'].keys())}")
    print("\n".join(out))
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    cmd = argv[1]
    if cmd == "parse" and len(argv) == 3:
        return cmd_parse(Path(argv[2]))
    if cmd == "compare" and len(argv) == 4:
        return cmd_compare(Path(argv[2]), Path(argv[3]))
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
