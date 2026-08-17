#!/usr/bin/env python3
"""
mine_slow_tests.py — where does the slow-test-run time actually live?

BL-135 precondition. The verification study established that 11% of test
invocations run over 60 s and consume 67% of all test-run time (46.1 h). That is a
corpus-wide aggregate and it does not say WHERE. This script breaks the >60 s tail
down by project and by command shape, which is what decides the remedy:

  concentrated in a few E2E specs      -> spec-level fix; module-map.json cannot reach it
  concentrated in full-suite unit runs -> affected-test selection is the right lever
  spread evenly                        -> selection buys less than the headline; re-scope

Read-only. Walks ~/.claude/projects/*/*.jsonl directly; touches no project.

METHOD

Duration is the wall-clock between the assistant message carrying a `Bash` tool_use
and the user message carrying that tool_use_id's tool_result. Both timestamps are
recorded by the harness, so this is measured, not inferred.

TRAPS HANDLED (the same class that killed five claims in the parent study)

  - A test command inside a larger shell line (`cd x && pytest`) still counts; the
    regex is unanchored, so `&&`-chains are not silently dropped.
  - Interrupted / never-answered tool_uses have no result and are excluded rather
    than counted as zero — a zero would drag the median down.
  - Durations over 1 h are dropped as clock artifacts (a session resumed the next
    day pairs a stale tool_use with a fresh result). Reported as a dropped count,
    never silently.
  - "Names a selector" is deliberately narrow: a path-like argument, a `-k`/`-t`
    filter, or a `--grep`. `--reporter`, `-v`, `--run` and friends are NOT selectors,
    and matching any bare flag would have called almost every run targeted.
"""
import json, os, glob, re, sys, datetime, argparse
from collections import defaultdict, Counter
import statistics as st

TX_ROOT = os.environ.get("CLAUDE_PROJECTS_ROOT") or os.path.expanduser("~/.claude/projects")

# The runner vocabulary is IMPORTED, not copied. It used to be a second copy with a
# comment claiming it was "kept in sync with mine_verification.py, deliberately" —
# a file that lives only under .context/audits/2026-06-21-usage-retro/ and is
# documented as not re-runnable. Nothing was keeping them in sync, and they had in
# fact diverged: mine_items matched none of `npm run test`, `yarn test`, `tox`,
# `go test`, `cargo test`.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mine_items as _MI  # noqa: E402
TESTCMD = _MI.TESTCMD

# A selector NARROWS the run. Flags that only change reporting are not selectors.
PATHLIKE = re.compile(r'(?<![-\w])[\w./-]*\.(py|ts|tsx|js|jsx|vue|spec|test)\b'
                      r'|(?<![-\w])(tests?|spec|e2e)/[\w./-]+')
FILTER = re.compile(r'(^|\s)(-k|-t|--grep|--testNamePattern|--test-name-pattern)(\s|=)')

E2E = re.compile(r'\b(playwright|test-e2e|cypress|e2e)\b')

SLOW_S = 60.0
MAX_S = 3600.0


def project_of(dirname):
    """~/.claude/projects/-Users-...-projects-<name> -> <name>."""
    m = re.search(r'projects-([\w.-]+)$', dirname)
    return m.group(1) if m else dirname


def parse_ts(s):
    if not s:
        return None
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


def bash_commands(obj):
    """(tool_use_id, command) for every Bash tool_use on an assistant message."""
    out = []
    content = obj.get("message", {}).get("content")
    if not isinstance(content, list):
        return out
    for b in content:
        if not isinstance(b, dict) or b.get("type") != "tool_use":
            continue
        if b.get("name") != "Bash":
            continue
        cmd = (b.get("input") or {}).get("command")
        if isinstance(cmd, str):
            out.append((b.get("id"), cmd))
    return out


def result_ids(obj):
    content = obj.get("message", {}).get("content")
    if not isinstance(content, list):
        return []
    return [b.get("tool_use_id") for b in content
            if isinstance(b, dict) and b.get("type") == "tool_result"]


def shape(cmd):
    """How the command selects, not which runner it uses."""
    if E2E.search(cmd):
        return "e2e"
    if FILTER.search(cmd) or PATHLIKE.search(cmd):
        return "targeted"
    return "full-suite"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--transcripts-root", default="",
                    help=f"Claude Code transcript root (default: {TX_ROOT})")
    args = ap.parse_args()
    tx_root = (os.path.abspath(os.path.expanduser(args.transcripts_root))
               if args.transcripts_root else TX_ROOT)

    runs = []           # (project, seconds, cmd, shape)
    dropped_long = 0
    unanswered = 0

    for d in sorted(glob.glob(tx_root + "/*/")):
        proj = project_of(os.path.basename(d.rstrip("/")))
        for f in glob.glob(d + "*.jsonl"):
            pending = {}    # tool_use_id -> (ts, cmd)
            try:
                fh = open(f, errors="replace")
            except OSError:
                continue
            with fh:
                for line in fh:
                    try:
                        o = json.loads(line)
                    except (ValueError, TypeError):
                        continue
                    ts = parse_ts(o.get("timestamp"))
                    role = o.get("type")
                    if role == "assistant":
                        for tid, cmd in bash_commands(o):
                            if tid and ts and TESTCMD.search(cmd):
                                pending[tid] = (ts, cmd)
                    elif role == "user":
                        for tid in result_ids(o):
                            if tid in pending and ts:
                                start, cmd = pending.pop(tid)
                                secs = (ts - start).total_seconds()
                                if secs < 0:
                                    continue
                                if secs > MAX_S:
                                    dropped_long += 1
                                    continue
                                runs.append((proj, secs, cmd, shape(cmd)))
            unanswered += len(pending)

    if not runs:
        print("no timed test invocations found", file=sys.stderr)
        return 1

    total = sum(r[1] for r in runs)
    slow = [r for r in runs if r[1] > SLOW_S]
    slow_t = sum(r[1] for r in slow)
    durs = sorted(r[1] for r in runs)

    def pct(v):
        return durs[min(len(durs) - 1, int(len(durs) * v))]

    print(f"timed test invocations : {len(runs)}   total {total/3600:.1f} h")
    print(f"  median {st.median(durs):.0f}s · p90 {pct(.90):.0f}s · p99 {pct(.99):.0f}s")
    print(f"  >{SLOW_S:.0f}s        : {len(slow)} ({len(slow)/len(runs)*100:.0f}%) "
          f"consuming {slow_t/3600:.1f} h ({slow_t/total*100:.0f}% of run time)")
    print(f"  excluded             : {unanswered} unanswered, {dropped_long} over {MAX_S/3600:.0f}h (clock artifacts)")

    print("\n== the >60s tail, by project ==")
    by_p = defaultdict(lambda: [0, 0.0])
    for p, s, _, _ in slow:
        by_p[p][0] += 1
        by_p[p][1] += s
    allp = defaultdict(lambda: [0, 0.0])
    for p, s, _, _ in runs:
        allp[p][0] += 1
        allp[p][1] += s
    print(f"{'project':28} {'slow n':>7} {'slow h':>8} {'% of tail':>10} {'all h':>8} {'slow share':>11}")
    for p, (n, t) in sorted(by_p.items(), key=lambda kv: -kv[1][1]):
        print(f"{p:28} {n:7d} {t/3600:8.1f} {t/slow_t*100:9.0f}% "
              f"{allp[p][1]/3600:8.1f} {t/allp[p][1]*100:10.0f}%")

    print("\n== the >60s tail, by selection shape ==")
    by_s = defaultdict(lambda: [0, 0.0])
    for _, s, _, sh in slow:
        by_s[sh][0] += 1
        by_s[sh][1] += s
    for sh, (n, t) in sorted(by_s.items(), key=lambda kv: -kv[1][1]):
        print(f"  {sh:12} {n:6d} runs  {t/3600:6.1f} h  {t/slow_t*100:3.0f}% of tail")

    print("\n== shape x project (tail hours) ==")
    grid = defaultdict(lambda: defaultdict(float))
    for p, s, _, sh in slow:
        grid[p][sh] += s
    shapes = ["e2e", "full-suite", "targeted"]
    print(f"{'project':28} " + " ".join(f"{s:>12}" for s in shapes))
    for p in sorted(grid, key=lambda p: -sum(grid[p].values()))[:12]:
        print(f"{p:28} " + " ".join(f"{grid[p][s]/3600:12.1f}" for s in shapes))

    print("\n== top slow commands (normalized, by total tail time) ==")
    norm = defaultdict(lambda: [0, 0.0])
    for p, s, cmd, _ in slow:
        c = re.sub(r'\s+', ' ', cmd.strip())[:90]
        norm[(p, c)][0] += 1
        norm[(p, c)][1] += s
    for (p, c), (n, t) in sorted(norm.items(), key=lambda kv: -kv[1][1])[:25]:
        print(f"  {t/3600:5.1f} h  n={n:4d}  mean={t/n:5.0f}s  [{p}] {c}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
