#!/usr/bin/env python3
"""context-snapshot.py — the measured input of `/aidex context`.

Runs Claude Code's own `/context` and `/skill-doctor` through `claude -p` in the project
cwd and merges their reports into one JSON. Both commands are local: no model call, zero
tokens, seconds to run, and they honour the cwd's `.claude/settings.local.json`, so the
result is this project's idle footprint as Claude Code itself measures it.

`/context` is the COST source: tokens per category, per memory file, per skill (built-ins
included) and per MCP tool. `/skill-doctor` adds USAGE only: invocations, days since last
use and tokens attributed over 7 days. Its usage columns are absent on HIPAA-regulated
or telemetry-disabled installs; that is a valid report, not a parse failure.

  context-snapshot.py [--out DIR] [--from-context FILE] [--from-doctor FILE] [--json]

Default `--out` is `_tmp/context-snapshot/<date>/`: raw `context.md`, `skill-doctor.txt`
and the merged `snapshot.json`. `--from-*` reads a saved report instead of running the
command (a pasted `/context` from a live long session, or a test fixture). `--json`
prints the merged JSON to stdout as well.

Read-only apart from `--out`. Exit 0 on a merged snapshot, 1 when `/context` could not be
obtained (a snapshot without cost is not a snapshot), 2 on a usage error.
"""
import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys

TOKEN_RX = re.compile(r"^\s*(~|<)?\s*([\d.,]+)\s*([km])?\s*$", re.I)
CLAUDE = os.environ.get("AIDEX_CLAUDE_BIN", "claude")


def parse_tokens(cell):
    """'~260' -> 260, '< 20' -> 20, '2.4k' -> 2400, '1.1m' -> 1100000, '-' -> None."""
    cell = cell.strip()
    if cell in ("", "-", "—"):
        return None
    m = TOKEN_RX.match(cell)
    if not m:
        return None
    n = float(m.group(2).replace(",", ""))
    unit = (m.group(3) or "").lower()
    n *= {"k": 1_000, "m": 1_000_000}.get(unit, 1)
    return int(round(n))


def md_tables(text):
    """Every markdown pipe table under its nearest heading: {heading: [row dicts]}."""
    out, heading, header, rows = {}, "", None, []

    def flush():
        if header and rows:
            out.setdefault(heading, []).extend(rows)

    for line in text.splitlines():
        s = line.strip()
        if s.startswith("#"):
            flush()
            heading, header, rows = s.lstrip("#").strip(), None, []
            continue
        if s.startswith("|"):
            cells = [c.strip() for c in s.strip("|").split("|")]
            if header is None:
                header = cells
            elif all(re.fullmatch(r":?-+:?", c) for c in cells):
                continue
            else:
                rows.append(dict(zip(header, cells)))
        else:
            flush()
            header, rows = None, []
    flush()
    return out


def parse_context(text):
    tables = md_tables(text)
    m = re.search(r"\*\*Tokens:\*\*\s*([\d.,]+[km]?)\s*/\s*([\d.,]+[km]?)", text, re.I)
    used = parse_tokens(m.group(1)) if m else None
    window = parse_tokens(m.group(2)) if m else None
    cats = {r["Category"].strip().lower().replace(" ", "-"): parse_tokens(r["Tokens"])
            for r in tables.get("Estimated usage by category", [])}
    return {
        "used_tokens": used,
        "window_tokens": window,
        "categories": cats,
        "mcp_tools": [{"tool": r["Tool"], "server": r["Server"], "tokens": parse_tokens(r["Tokens"])}
                      for r in tables.get("MCP Tools", [])],
        "memory_files": [{"type": r["Type"], "path": r["Path"], "tokens": parse_tokens(r["Tokens"])}
                         for r in tables.get("Memory Files", [])],
        "skills": {r["Skill"]: {"source": r["Source"], "tokens": parse_tokens(r["Tokens"])}
                   for r in tables.get("Skills", [])},
    }


DOCTOR_HEADER_RX = re.compile(r"^\s*skill\s+source\s+", re.I)


def parse_doctor(text):
    """Fixed-width table: columns are located from the header line's word offsets."""
    lines = text.splitlines()
    hdr_i = next((i for i, l in enumerate(lines) if DOCTOR_HEADER_RX.match(l)), None)
    if hdr_i is None:
        return {"usage_available": False, "skills": {}, "notes": [l.strip() for l in lines if l.strip()]}
    hdr = lines[hdr_i]
    # Column names as they appear; "7d tokens" and "last used" carry a space.
    names = [m.group(0) for m in re.finditer(r"7d tokens|last used|\S+", hdr)]
    starts = [hdr.index(n) for n in names]
    keys = [n.lower().replace(" ", "_") for n in names]
    usage = "uses" in keys or "7d_tokens" in keys
    skills, notes = {}, []
    for l in lines[hdr_i + 1:]:
        if not l.strip():
            continue
        if not l.startswith(" ") or l.strip().startswith(("context =", "(", "7d tokens =")):
            notes.append(l.strip())
            continue
        parts = re.split(r"\s{2,}", l.strip())
        if len(parts) < 2:
            notes.append(l.strip())
            continue
        row = dict(zip(keys, parts))
        entry = {"source": row.get("source"),
                 "listing_tokens": parse_tokens(row.get("context", "-"))}
        if usage:
            u = row.get("uses", "").rstrip("×x")
            entry["uses"] = int(u) if u.isdigit() else None
            entry["tokens_7d"] = parse_tokens(row.get("7d_tokens", "-"))
            entry["last_used"] = row.get("last_used")
        skills[row["skill"]] = entry
    return {"usage_available": usage, "skills": skills, "notes": notes}


def merge(ctx, doc):
    skills = {}
    for name, c in ctx["skills"].items():
        skills[name] = {"source": c["source"], "tokens": c["tokens"], "listed": True}
    for name, d in doc["skills"].items():
        s = skills.setdefault(name, {"source": d["source"], "tokens": d["listing_tokens"],
                                     "listed": d["listing_tokens"] is not None})
        for k in ("uses", "tokens_7d", "last_used"):
            if k in d:
                s[k] = d[k]
    return {
        "captured": dt.datetime.now().isoformat(timespec="seconds"),
        "cwd": os.getcwd(),
        "claude_version": claude_version(),
        "window_tokens": ctx["window_tokens"],
        "idle_tokens": ctx["used_tokens"],
        "categories": ctx["categories"],
        "memory_files": ctx["memory_files"],
        "mcp_tools": ctx["mcp_tools"],
        "usage_available": doc["usage_available"],
        "skills": skills,
        "skill_doctor_notes": doc["notes"],
    }


def claude_version():
    try:
        out = subprocess.run([CLAUDE, "--version"], capture_output=True, text=True, timeout=30).stdout
        m = re.search(r"\d+\.\d+\.\d+", out)
        return m.group(0) if m else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def run_command(cmd):
    """stdout of `claude -p <cmd>`, or None when it could not run."""
    try:
        r = subprocess.run([CLAUDE, "-p", cmd, "--output-format", "text"],
                           capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"ERROR: {cmd}: {exc}", file=sys.stderr)
        return None
    if r.returncode != 0:
        print(f"ERROR: {cmd} exited {r.returncode}: {r.stderr.strip()[:300]}", file=sys.stderr)
        return None
    return r.stdout


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join("_tmp", "context-snapshot", dt.date.today().isoformat()))
    ap.add_argument("--from-context", help="saved /context report instead of running it")
    ap.add_argument("--from-doctor", help="saved /skill-doctor report instead of running it")
    ap.add_argument("--json", action="store_true", help="print the merged snapshot to stdout")
    a = ap.parse_args()

    ctx_text = open(a.from_context).read() if a.from_context else run_command("/context")
    if not ctx_text or "Context Usage" not in ctx_text:
        sys.exit("ERROR: no /context report — a snapshot without cost is not a snapshot")
    doc_text = open(a.from_doctor).read() if a.from_doctor else run_command("/skill-doctor")
    if doc_text is None:
        doc_text = ""
        print("WARN: /skill-doctor unavailable; snapshot carries cost only", file=sys.stderr)

    snap = merge(parse_context(ctx_text), parse_doctor(doc_text))
    os.makedirs(a.out, exist_ok=True)
    for name, body in (("context.md", ctx_text), ("skill-doctor.txt", doc_text)):
        with open(os.path.join(a.out, name), "w") as f:
            f.write(body)
    with open(os.path.join(a.out, "snapshot.json"), "w") as f:
        json.dump(snap, f, indent=2)
    if a.json:
        print(json.dumps(snap, indent=2))
    n_sk = sum(1 for s in snap["skills"].values() if s.get("tokens"))
    print(f"snapshot: {a.out}/snapshot.json — idle {snap['idle_tokens']} of {snap['window_tokens']} tokens, "
          f"{n_sk} listed skills, {len(snap['memory_files'])} memory files, "
          f"usage {'available' if snap['usage_available'] else 'absent'}", file=sys.stderr)


if __name__ == "__main__":
    main()
