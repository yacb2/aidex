#!/usr/bin/env python3
"""census.py — is the testing canon in context before a test is written?

Two numbers, one command:

  1. Of the sessions that wrote or edited a test file in the window, how many had
     the testing core in context BEFORE their first test write, split by whether
     that first write was made in the main session or in a subagent.
  2. Of the `fix*` commits in the given repos, how many touch a test file and how
     many carry a `RED` proof line.

"Core in context" is judged per context: a subagent starts fresh, so a skill the
main session loaded does not count for a write the subagent makes. Signals:
  - a Skill tool_use of testing or bugfix (testing, aidex:testing, aidex-testing),
  - a typed slash command of the same (<command-name>/aidex:testing</command-name>),
  - the skill's isMeta "Base directory for this skill: .../skills/testing" text,
  - a Read of a file under skills/testing/,
  - the subagent's type is an agent whose frontmatter `skills:` names testing
    (read from --agents-dir, default ~/.claude/agents; --preloaded-agents overrides).
A test file is what the first-test-write hook gates: test_*.py, *_test.py,
*.{spec,test}.{ts,tsx,js,jsx,mjs,cjs}, test-*.sh, or *.sh under a tests/ dir (not conftest.py,
fixtures, helpers). The hook's deny is NOT a signal: its reason only points to the
skill, so counting it would measure "the hook fired" (~100% after install by
construction); the Skill load or Read it leads to is what counts. A test write is
a Write or Edit to one; a write whose tool_result is an error (denied) is not a
write, and a write event replayed into a resumed or forked transcript (same uuid)
counts once.

Transcripts are ~/.claude/projects/<project>/<session>.jsonl, with subagents at
<project>/<session>/subagents/*.jsonl (+ .meta.json carrying agentType). Events are
windowed by their own timestamp. Experiment copies are skipped (project dirs
containing -tmp-, _tmp, worktrees-agent, e1-wt, rehearsal) unless --include-all;
eval runs under /private/tmp need it. Transcripts with 0 counted sessions exit 1
instead of printing 0/0.

Usage:
  census.py --since 2026-08-26 [--until 2026-09-25] [--transcripts DIR]
            [--agents-dir DIR ...] [--preloaded-agents a,b] [--include-all]
            [--tsv sessions.tsv] [--repos PATH ...]
"""
import argparse, datetime, glob, json, os, re, subprocess, sys

EXCLUDE = ("-tmp-", "_tmp", "worktrees-agent", "e1-wt", "rehearsal")
TEST_RE = re.compile(
    r"(^|/)(test_[^/]*\.py|[^/]*_test\.py|[^/]*\.(spec|test)\.(ts|tsx|js|jsx|mjs|cjs)|test-[^/]*\.sh)$"
    r"|(^|/)tests/([^/]+/)*[^/]*\.sh$")
WRITE_TOOLS = ("Write", "Edit")
SKILL_RE = re.compile(r"(^|:)(aidex[:-])?(testing|bugfix)$")
COMMAND_RE = re.compile(r"<command-name>/([^<\s]+)</command-name>")
BASEDIR_RE = re.compile(r"^Base directory for this skill: \S*/skills/(testing|bugfix)/?$", re.M)


def is_test(path):
    return bool(TEST_RE.search(path))


def text_of(content):
    if isinstance(content, str):
        return content
    return "\n".join(b.get("text", "") for b in content
                     if isinstance(b, dict) and b.get("type") == "text")


def preloaded_agents(dirs):
    """Agent names whose frontmatter `skills:` names testing (bare or aidex:)."""
    names = set()
    for d in dirs:
        for f in glob.glob(os.path.join(os.path.expanduser(d), "*.md")):
            m = re.match(r"---\n(.*?)\n---", open(f, errors="replace").read(), re.S)
            if not m:
                continue
            fm = m.group(1)
            sk = re.search(r"^skills:(.*(?:\n[ \t]+-.*)*)", fm, re.M)
            if sk and {"testing", "aidex:testing"} & set(re.findall(r"[\w:.-]+", sk.group(1))):
                nm = re.search(r"^name:\s*(\S+)", fm, re.M)
                names.add(nm.group(1) if nm else os.path.basename(f)[:-3])
    return names


def scan(path, since, until, preloaded):
    """One context -> (in-window test writes [(ts, event uuid)], first core ts or None)."""
    events = []
    for line in open(path, errors="replace"):
        try:
            o = json.loads(line)
        except ValueError:
            continue
        if isinstance(o, dict) and isinstance((o.get("message") or {}).get("content"), (list, str)):
            events.append(o)
    errored, core = set(), [] if not preloaded else [""]
    for o in events:
        content, ts = o["message"]["content"], o.get("timestamp", "")
        if o.get("type") == "user":
            text = text_of(content)
            cmd = COMMAND_RE.search(text)
            if (cmd and SKILL_RE.search(cmd.group(1))) or (o.get("isMeta") and BASEDIR_RE.search(text)):
                core.append(ts)
        if isinstance(content, str):
            continue
        for b in content:
            if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("is_error"):
                errored.add(b.get("tool_use_id"))
    writes = []
    for o in events:
        ts = o.get("timestamp", "")
        if isinstance(o["message"]["content"], str):
            continue
        for b in o["message"]["content"]:
            if not (isinstance(b, dict) and b.get("type") == "tool_use"):
                continue
            name, inp = b.get("name"), b.get("input") or {}
            if name == "Skill" and SKILL_RE.search(str(inp.get("skill", ""))):
                core.append(ts)
            elif name == "Read" and "skills/testing/" in str(inp.get("file_path", "")):
                core.append(ts)
            elif (name in WRITE_TOOLS and b.get("id") not in errored
                  and since <= ts[:10] <= until
                  and is_test(str(inp.get("file_path", "")))):
                writes.append((ts, o.get("uuid") or f"{path}:{b.get('id')}"))
    return writes, (min(core) if core else None)


def sessions(root, since, until, preloaded, include_all):
    # A resumed or forked session is a new file that replays the old events with
    # their uuids; a write event is counted once, in the first file that has it.
    seen = set()
    for main in sorted(glob.glob(os.path.join(root, "*", "*.jsonl"))):
        project = os.path.basename(os.path.dirname(main))
        if not include_all and any(x in project for x in EXCLUDE):
            continue
        sid = os.path.basename(main)[:-6]
        contexts = [("main", main, False)]
        for sub in sorted(glob.glob(os.path.join(main[:-6], "subagents", "*.jsonl"))):
            try:
                kind = json.load(open(sub[:-6] + ".meta.json")).get("agentType", "")
            except (OSError, ValueError):
                kind = ""
            contexts.append(("subagent", sub, kind.split(":")[-1] in preloaded))
        first, n, anywhere = None, 0, False
        for who, path, pre in contexts:
            writes, c = scan(path, since, until, pre)
            writes = [(ts, u) for ts, u in writes if u not in seen]
            seen.update(u for _, u in writes)
            n += len(writes)
            w = min(writes)[0] if writes else None
            anywhere = anywhere or c is not None
            if w and (first is None or w < first[0]):
                first = (w, who, c is not None and c <= w)
        if first:
            yield {"project": project, "session_id": sid, "date": first[0][:10],
                   "n_test_writes": n, "first_writer": first[1],
                   "core_anywhere": "y" if anywhere else "n",
                   "core_before_first_test_write": "y" if first[2] else "n"}


def fix_commits(repo, since, until):
    out = subprocess.run(
        ["git", "-C", repo, "log", "--no-merges", "--name-only",
         "--format=%x1e%as%x1f%B%x1f"], capture_output=True, text=True, check=True).stdout
    fix = test = red = 0
    for rec in out.split("\x1e")[1:]:
        date, body, files = rec.split("\x1f")
        if not (since <= date <= until and re.match(r"fix\b", body.lstrip())):
            continue
        fix += 1
        test += any(is_test(f) for f in files.split())
        red += bool(re.search(r"\bRED\b", body))
    return fix, test, red


def pct(a, b):
    return f"{a}/{b} ({100 * a // b if b else 0}%)"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--transcripts", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--since", required=True)
    ap.add_argument("--until", default=datetime.date.today().isoformat())
    ap.add_argument("--agents-dir", action="append")
    ap.add_argument("--preloaded-agents", default="")
    ap.add_argument("--include-all", action="store_true")
    ap.add_argument("--tsv")
    ap.add_argument("--repos", nargs="*", default=[])
    a = ap.parse_args()
    preloaded = ({x.strip() for x in a.preloaded_agents.split(",") if x.strip()}
                 or preloaded_agents(a.agents_dir or ["~/.claude/agents"]))

    rows = list(sessions(a.transcripts, a.since, a.until, preloaded, a.include_all))
    if not rows and glob.glob(os.path.join(a.transcripts, "*", "*.jsonl")):
        sys.exit(f"census: transcripts exist in {a.transcripts} but 0 test-writing sessions "
                 f"{a.since}..{a.until} were counted"
                 + ("" if a.include_all else f"; experiment dirs ({', '.join(EXCLUDE)}) "
                    "are skipped, pass --include-all for eval runs"))
    yes = [r for r in rows if r["core_before_first_test_write"] == "y"]
    print(f"Sessions with a test write {a.since}..{a.until}: {len(rows)}")
    print(f"  core before first test write: {pct(len(yes), len(rows))}")
    for who in ("main", "subagent"):
        n = sum(r["first_writer"] == who for r in rows)
        k = sum(r["first_writer"] == who for r in yes)
        print(f"  first write in {who}: {n}, core before: {k}")
    print(f"  core anywhere in session: {pct(sum(r['core_anywhere'] == 'y' for r in rows), len(rows))}")
    if a.tsv:
        with open(a.tsv, "w") as fh:
            cols = list(rows[0]) if rows else ["project", "session_id"]
            fh.write("\t".join(cols) + "\n")
            for r in rows:
                fh.write("\t".join(str(r[c]) for c in cols) + "\n")

    if a.repos:
        print(f"\nFix commits {a.since}..{a.until}: repo  fix  with_test  with_RED")
        tot = [0, 0, 0]
        for repo in a.repos:
            f, t, r = fix_commits(repo, a.since, a.until)
            tot = [tot[0] + f, tot[1] + t, tot[2] + r]
            print(f"{repo}  {f}  {t}  {r}")
        print(f"total  {tot[0]}  {tot[1]}  {tot[2]}")


if __name__ == "__main__":
    main()
