#!/usr/bin/env python3
"""
mine_errors.py — what is actually FAILING in the field.

Read-only over ~/.claude/projects. For every tool_result marked is_error inside
the window, emit a normalized signature so failures cluster instead of scrolling.

Two views:
  1. by tool          — which tool errors most
  2. by signature     — the recurring failure text, normalized (paths/ids scrubbed)

Aidex-specific view: any error whose signature mentions an aidex script, skill or
`.context/` path is tagged `aidex:` so suite defects separate from ambient noise.

Usage:  mine_errors.py [--since ISO] [--days N] [--top N]
"""
import json, os, glob, re, argparse, datetime
from collections import Counter, defaultdict

TX_ROOT = os.environ.get("CLAUDE_PROJECTS_ROOT") or os.path.expanduser("~/.claude/projects")

# scrub volatile bits so the same failure collapses to one signature
SCRUB = [
    (re.compile(r"/Users/[^\s'\"]+"), "<path>"),
    (re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"), "<uuid>"),
    (re.compile(r"\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}[:\d.]*\b"), "<ts>"),
    (re.compile(r"\b\d{4}-\d{2}-\d{2}\b"), "<date>"),
    (re.compile(r"\b\d{3,}\b"), "<n>"),
    (re.compile(r"line \d+"), "line <n>"),
    (re.compile(r"\s+"), " "),
]

AIDEX_HINT = re.compile(
    r"aidex|\.context/|register-item|close-plan|reindex-|worktree\.sh|validate\.py|"
    r"new-(loop|workflow|communication|worktree)|orphan-sweep|render\.sh|"
    r"\.aidex-waivers|durability|MEMORY\.md",
    re.I,
)


def parse_ts(s):
    """An AWARE datetime, or None. A naive input is read as UTC.

    Taken verbatim from extract.py, which fixed this first. `fromisoformat`
    returns an aware value only when the string carries a Z or an explicit
    offset, so the DOCUMENTED plain form (`--since 2026-08-19`) produced a naive
    cutoff that raised TypeError on the first file mtime comparison. `--days`
    happened to work, so the crash lived only in the invocation the reference
    prints. This copy diverged because the file sat outside the tracked tree with
    no test to run against it -- the same cost BL-165 named for extract.py."""
    try:
        t = datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None
    return t if t.tzinfo else t.replace(tzinfo=datetime.timezone.utc)


def short_project(name):
    return (name.replace("-Users-yoelacevedo-Documents-projects-", "")
                .replace("-Users-yoelacevedo-", "~/"))


def normalize(txt):
    s = txt.strip()
    for rx, rep in SCRUB:
        s = rx.sub(rep, s)
    return s[:220]


def tool_name_for(objs_by_id, tuid):
    return objs_by_id.get(tuid, "?")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default=None)
    ap.add_argument("--days", type=int, default=15)
    ap.add_argument("--top", type=int, default=40)
    ap.add_argument("--json", default=None, help="write full records here")
    ap.add_argument("--transcripts-root", default="",
                    help=f"Claude Code transcript root (default: {TX_ROOT})")
    args = ap.parse_args()
    root = (os.path.abspath(os.path.expanduser(args.transcripts_root))
            if args.transcripts_root else TX_ROOT)

    now = datetime.datetime.now(datetime.timezone.utc)
    cutoff = parse_ts(args.since) if args.since else now - datetime.timedelta(days=args.days)

    by_tool = Counter()
    by_sig = Counter()
    sig_projects = defaultdict(set)
    sig_example = {}
    sig_last = {}
    records = []

    for d in glob.glob(root + "/*/"):
        proj = short_project(os.path.basename(d.rstrip("/")))
        for f in glob.glob(d + "*.jsonl"):
            try:
                if datetime.datetime.fromtimestamp(os.path.getmtime(f),
                        datetime.timezone.utc) < cutoff:
                    continue
            except OSError:
                continue
            # map tool_use id -> tool name, then match tool_result by id
            names = {}
            try:
                fh = open(f)
            except OSError:
                continue
            with fh:
                for line in fh:
                    if not line.strip():
                        continue
                    try:
                        o = json.loads(line)
                    except Exception:
                        continue
                    typ = o.get("type")
                    content = o.get("message", {}).get("content")
                    if not isinstance(content, list):
                        continue
                    if typ == "assistant":
                        for b in content:
                            if isinstance(b, dict) and b.get("type") == "tool_use":
                                names[b.get("id")] = b.get("name", "?")
                        continue
                    if typ != "user":
                        continue
                    ts = parse_ts(o.get("timestamp", ""))
                    if not ts or ts < cutoff:
                        continue
                    for b in content:
                        if not (isinstance(b, dict) and b.get("type") == "tool_result"):
                            continue
                        if not b.get("is_error"):
                            continue
                        c = b.get("content")
                        if isinstance(c, list):
                            c = "\n".join(x.get("text", "") for x in c
                                          if isinstance(x, dict))
                        if not isinstance(c, str):
                            c = str(c)
                        tool = names.get(b.get("tool_use_id"), "?")
                        sig = normalize(c)
                        tag = "aidex:" if AIDEX_HINT.search(c) else ""
                        key = f"{tag}{tool} :: {sig}"
                        by_tool[tool] += 1
                        by_sig[key] += 1
                        sig_projects[key].add(proj)
                        sig_last[key] = max(sig_last.get(key, ""), ts.isoformat())
                        sig_example.setdefault(key, c[:400])
                        records.append({"project": proj, "ts": ts.isoformat(),
                                        "tool": tool, "sig": sig, "aidex": bool(tag),
                                        "text": c[:600]})

    total = sum(by_tool.values())
    print(f"errored tool_results: {total}  (window from {cutoff.isoformat()[:19]})")
    print("\n=== by tool ===")
    for t, n in by_tool.most_common(20):
        print(f"  {n:5d}  {t}")

    aidex_sigs = [(k, n) for k, n in by_sig.items() if k.startswith("aidex:")]
    aidex_sigs.sort(key=lambda kv: -kv[1])
    print(f"\n=== AIDEX-implicated signatures ({sum(n for _, n in aidex_sigs)} errors,"
          f" {len(aidex_sigs)} distinct) ===")
    for k, n in aidex_sigs[:args.top]:
        projs = ",".join(sorted(sig_projects[k])[:4])
        print(f"\n  [{n}x] last={sig_last[k][:16]} projects={projs}\n     {k[:200]}")

    print(f"\n=== top signatures overall ===")
    for k, n in by_sig.most_common(args.top):
        projs = ",".join(sorted(sig_projects[k])[:4])
        print(f"  [{n}x] {projs} :: {k[:170]}")

    if args.json:
        with open(args.json, "w") as fh:
            for r in records:
                fh.write(json.dumps(r, ensure_ascii=False) + "\n")
        print(f"\nwrote {args.json} ({len(records)} records)")


if __name__ == "__main__":
    main()
