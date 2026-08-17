#!/usr/bin/env python3
"""orient-audit — did the orientation block actually reach the user?

This is Compass's reconciliation instrument for v0.28.0. It reads Claude Code
session transcripts ONLY and imports no Compass code, so it cannot agree with
the implementation by construction: it measures observed behaviour, not the
product's opinion of itself.

Pinned gold (the pre-change baseline, measured 2026-08-17):
    /compass:go  ->  0 orientation blocks across 30 invocations
    window 2026-07-30..2026-08-14, 5 projects

Re-running it over that same window must still return 0/30. The past cannot
change; a different answer means this scanner drifted, not the product.

Post-ship bound: over the next >=5 real front-door invocations after ship, the
ratio must be 5/5, reported PER COMMAND so /compass:status and /compass:resume
are not hidden behind /compass:go's numbers.

Usage:
    orient-audit.py [--window YYYY-MM-DD:YYYY-MM-DD] [--root DIR] [--json]
"""
import argparse
import json
import os
import re
import sys

CMD_RE = re.compile(r"<command-name>\s*/?(compass:go|compass:status|compass:resume)\s*</command-name>")

# The marker set MUST cover the OLD welcome text and the NEW rendered blocks --
# a MID-BUILD block is a PASS, not a miss. Getting this wrong is the single
# likeliest way to produce a wrong number here (contract bug-class checklist).
MARKERS = (
    # v0.15-v0.27 hand-written welcome (what the baseline was measured against)
    "Three commands are all you need",
    "how Compass works",
    # v0.28 script-rendered blocks
    "Build true to a spec you lock first",
    "Three doors:",
    "── Compass ·",
    "── Compass ─",
)


def blocks(msg):
    if not msg:
        return []
    c = msg.get("content")
    if isinstance(c, str):
        return [("text", c)]
    out = []
    if isinstance(c, list):
        for b in c:
            if isinstance(b, dict):
                t = b.get("type")
                if t == "text":
                    out.append(("text", b.get("text") or ""))
                elif t == "tool_result":
                    out.append(("tool_result", ""))
    return out


def scan(root, lo, hi):
    seen = set()          # (session_file, timestamp) -- never double-count a resumed copy
    rows = []
    for dirpath, _, files in os.walk(root):
        for fn in files:
            if not fn.endswith(".jsonl"):
                continue
            path = os.path.join(dirpath, fn)
            recs = []
            try:
                with open(path, errors="replace") as fh:
                    for ln in fh:
                        ln = ln.strip()
                        if not ln:
                            continue
                        try:
                            recs.append(json.loads(ln))
                        except Exception:
                            pass
            except Exception:
                continue
            for i, r in enumerate(recs):
                if r.get("type") != "user":
                    continue
                m = CMD_RE.search(json.dumps(r.get("message", ""))[:3000])
                if not m:
                    continue
                ts = r.get("timestamp", "") or ""
                day = ts[:10]
                if lo and day and day < lo:
                    continue
                if hi and day and day > hi:
                    continue
                key = (os.path.basename(path), ts)
                if key in seen:
                    continue
                seen.add(key)
                texts = []
                j, steps = i + 1, 0
                while j < len(recs) and steps < 250:
                    rj = recs[j]
                    if rj.get("type") == "assistant":
                        texts += [t for k, t in blocks(rj.get("message")) if k == "text" and t.strip()]
                    elif rj.get("type") == "user" and not rj.get("isMeta"):
                        bl = blocks(rj.get("message"))
                        if not any(k == "tool_result" for k, _ in bl):
                            txt = "\n".join(t for k, t in bl if k == "text")
                            if "<local-command" not in txt and "<command-name>" not in txt:
                                break
                    j += 1
                    steps += 1
                blob = "\n".join(texts)
                rows.append({"cmd": m.group(1), "ts": ts, "shown": any(k in blob for k in MARKERS)})
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--window", default="", help="YYYY-MM-DD:YYYY-MM-DD (inclusive)")
    ap.add_argument("--root", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    lo = hi = ""
    if a.window:
        parts = a.window.split(":")
        lo = parts[0]
        hi = parts[1] if len(parts) > 1 else ""

    if not os.path.isdir(a.root):
        print(f"orient-audit: no transcript root at {a.root} — N/A", file=sys.stderr)
        return 0

    rows = scan(a.root, lo, hi)
    per = {}
    for r in rows:
        d = per.setdefault(r["cmd"], {"shown": 0, "total": 0})
        d["total"] += 1
        d["shown"] += 1 if r["shown"] else 0

    if a.json:
        print(json.dumps({"window": a.window or "all", "per_command": per,
                          "total": {"shown": sum(v["shown"] for v in per.values()),
                                    "total": sum(v["total"] for v in per.values())}}, indent=2))
        return 0

    print(f"orient-audit · window {a.window or 'all'} · root {a.root}")
    if not per:
        print("  (no front-door invocations found in this window)")
        return 0
    for cmd in sorted(per):
        v = per[cmd]
        print(f"  /{cmd:16s} {v['shown']}/{v['total']} orientation blocks shown")
    tot_s = sum(v["shown"] for v in per.values())
    tot_t = sum(v["total"] for v in per.values())
    print(f"  {'ALL':17s} {tot_s}/{tot_t}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
