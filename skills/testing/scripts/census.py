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
a Write, Edit or MultiEdit to one, or a Bash command that writes one (bash_writes, the
detector the hook imports); a write whose tool_result is an error (denied) is not a
write — except a Bash result "Exit code N", which ran — and a write event replayed into
a resumed or forked transcript (same uuid) counts once.

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
import argparse, datetime, glob, json, os, re, shlex, subprocess, sys

EXCLUDE = ("-tmp-", "_tmp", "worktrees-agent", "e1-wt", "rehearsal")
TEST_RE = re.compile(
    r"(^|/)(test_[^/]*\.py|[^/]*_test\.py|[^/]*\.(spec|test)\.(ts|tsx|js|jsx|mjs|cjs)|test-[^/]*\.sh)$"
    r"|(^|/)tests/([^/]+/)*[^/]*\.sh$")
WRITE_TOOLS = ("Write", "Edit", "MultiEdit")
# Bash writes: hooks/first-test-write-gate.sh imports bash_writes from here, so the hook
# gates exactly what the census counts.
OPS = sorted(["<<<", "<<-", "&>>", "<<", ">>", ">|", "&>", ">&", "<&", "<>", "&&", "||", "|&",
              ";;", ";", "&", "|", "<", ">", "(", ")"], key=len, reverse=True)
WRITE_REDIRECTS = (">", ">>", ">|", "&>", "&>>")
KEYWORDS = ("{", "!", "if", "then", "else", "elif", "do", "while", "until", "time")
PY_ASSIGN_RE = re.compile(
    r"(?:^|;)[ \t]*(\w+)[ \t]*=(?!=)[ \t]*(?:(?:Path\([ \t]*)?(['\"])([^'\"\n]+)\2)?", re.M)
PY_OPEN_RE = re.compile(
    r"\bopen\(\s*(?:(['\"])([^'\"\n]+)\1|(\w+))\s*,\s*(?:mode\s*=\s*)?['\"][rbt+]*[wax]")
PY_WRITE_RE = re.compile(r"(?:\bPath\(\s*(['\"])([^'\"\n]+)\1\s*\)|\b(\w+))\.write_(?:text|bytes)\(")
VAR_RE = re.compile(r"\$(?:\{(\w+)\}|(\w+))")
SKILL_RE = re.compile(r"(^|:)(aidex[:-])?(testing|bugfix)$")
COMMAND_RE = re.compile(r"<command-name>/([^<\s]+)</command-name>")
BASEDIR_RE = re.compile(r"^Base directory for this skill: \S*/skills/(testing|bugfix)/?$", re.M)


def is_test(path):
    return bool(TEST_RE.search(path))


def _py_writes(code):
    """Paths a Python snippet opens for writing: open(path, 'w'|'a'|'x'...) and
    Path(path).write_text/bytes, the path a literal or a name, resolved against the
    assignment in effect at that point (a name last assigned a non-literal is skipped)."""
    events = [(m.start(), "=", m.group(1), m.group(3)) for m in PY_ASSIGN_RE.finditer(code)]
    events += [(m.start(), "w", m.group(3), m.group(2))
               for r in (PY_OPEN_RE, PY_WRITE_RE) for m in r.finditer(code)]
    names, found = {}, []
    for _, kind, name, lit in sorted(events, key=lambda e: e[0]):
        if kind == "=":
            names[name] = lit
        elif lit or names.get(name):
            found.append(lit or names[name])
    return found


def _lex(s):
    """Shell words and operators; quotes removed, comments dropped, $(...) and `...`
    kept inside their word, the fd of `2>` dropped. A heredoc operator token carries its
    body. Raises on unterminated quotes."""
    toks, pending, word, inword, i, n = [], [], "", False, 0, len(s)

    def end():
        nonlocal word, inword
        if inword:
            toks.append({"w": word})
            if pending and "delim" not in pending[-1]:  # the word after << is its delimiter
                pending[-1]["delim"] = word
        word, inword = "", False

    while i < n:
        c = s[i]
        if c == "\\" and i + 1 < n:
            if s[i + 1] != "\n":
                word, inword = word + s[i + 1], True
            i += 2
        elif c == "'":
            j = s.index("'", i + 1)
            word, inword, i = word + s[i + 1:j], True, j + 1
        elif c == '"':
            j = i + 1
            while s[j] != '"':
                if s[j] == "\\" and s[j + 1] in '"\\$`':
                    j += 1
                word += s[j]
                j += 1
            inword, i = True, j + 1
        elif c == "`" or s.startswith("$(", i):
            j, depth = i + 1, 0
            if c == "`":
                j = s.index("`", j) + 1
            else:
                while True:
                    depth += {"(": 1, ")": -1}.get(s[j], 0)
                    j += 1
                    if depth == 0:
                        break
            word, inword, i = word + s[i:j], True, j
        elif c == "#" and not inword:
            while i < n and s[i] != "\n":
                i += 1
        elif c in " \t\r":
            end()
            i += 1
        elif c == "\n":
            end()
            toks.append({"op": "\n"})
            i += 1
            for tok in pending:  # heredoc bodies start on the next line, in order
                body = []
                while i < n:
                    j = s.find("\n", i)
                    j = n if j < 0 else j
                    line, i = s[i:j], j + 1
                    if (line.lstrip("\t") if tok["op"] == "<<-" else line) == tok.get("delim"):
                        break
                    body.append(line)
                tok["body"] = "\n".join(body)
            pending = []
        elif any(s.startswith(o, i) for o in OPS):
            op = next(o for o in OPS if s.startswith(o, i))
            if inword and word.isdigit() and ("<" in op or ">" in op):
                word, inword = "", False  # the fd of 2>
            end()
            toks.append({"op": op})
            if op in ("<<", "<<-"):
                pending.append(toks[-1])
            i += len(op)
        else:
            word, inword = word + c, True
            i += 1
    end()
    return toks


def bash_writes(cmd, cwd=None):
    """Paths a Bash command writes: `>`/`>>` redirection targets (heredocs included),
    tee, touch, and open()/write_text() inside `python -` heredocs and `python -c`.
    cp/mv are left out: they copy or move a test, they do not author one.
    Relative paths follow `cd`/`pushd`/`popd` and `( )` subshells from cwd (or stay
    relative when cwd is None); `$VAR` assigned earlier in the command is substituted.
    A path still holding a `$` is unknown: the hook never denies it, the census counts
    it if it looks like a test. [] on anything it cannot parse."""
    try:
        toks = _lex(cmd.replace("\r\n", "\n"))
    except Exception:
        return []
    try:
        state = {"cwd": cwd or "", "vars": {}}
        dirs, subshells, out = [], [], []

        def sub(w):
            return VAR_RE.sub(lambda m: state["vars"].get(m.group(1) or m.group(2), m.group(0)), w)

        def resolve(p, base=None):
            p = os.path.expanduser(sub(p))
            base = state["cwd"] if base is None else base
            if os.path.isabs(p) or not base:
                return os.path.normpath(p) if "$" not in p else p
            if "$" in base:
                return base.rstrip("/") + "/" + p
            return os.path.normpath(os.path.join(base, p))

        def command(words, bodies):
            while words and words[0] in KEYWORDS:
                words = words[1:]
            if words and words[0] in ("export", "readonly", "declare", "local"):
                words = [w for w in words[1:] if not w.startswith("-")]
                if not all("=" in w for w in words):
                    return
            assigns = []
            while words and re.match(r"\w+=", words[0]):
                assigns.append(words[0])
                words = words[1:]
            if not words:  # a bare assignment sets a shell variable
                for a in assigns:
                    k, v = a.split("=", 1)
                    state["vars"][k] = sub(v)
                return
            name, args = os.path.basename(words[0]), words[1:]
            paths = [a for a in args if not a.startswith("-")]
            if name in ("cd", "pushd"):
                target = paths[0] if paths else "~"
                if name == "pushd":
                    dirs.append(state["cwd"])
                state["cwd"] = "$OLDPWD" if target == "-" else resolve(target)
            elif name == "popd":
                state["cwd"] = dirs.pop() if dirs else "$OLDPWD"
            elif name in ("tee", "touch"):
                out.extend(resolve(p) for p in paths)
            elif re.fullmatch(r"python[\d.]*", name):
                code = bodies + ([args[args.index("-c") + 1]] if "-c" in args[:-1] else [])
                out.extend(resolve(p) for c in code for p in _py_writes(c))

        words, bodies, i = [], [], 0
        while i < len(toks):
            t = toks[i]
            op = t.get("op")
            if op is None:
                words.append(t["w"])
            elif op in WRITE_REDIRECTS or op in ("<<", "<<-") or "<" in op or ">" in op:
                nxt = toks[i + 1].get("w") if i + 1 < len(toks) else None
                if op in WRITE_REDIRECTS and nxt is not None:
                    out.append(resolve(nxt))
                if op in ("<<", "<<-"):
                    bodies.append(t.get("body", ""))
                i += 1 if nxt is None else 2
                continue
            else:
                command(words, bodies)
                words, bodies = [], []
                if op == "(":
                    subshells.append((state["cwd"], dict(state["vars"])))
                elif op == ")" and subshells:
                    state["cwd"], state["vars"] = subshells.pop()
            i += 1
        command(words, bodies)
        return out
    except Exception:
        return []


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
    errored, core = {}, [] if not preloaded else [""]
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
                errored[b.get("tool_use_id")] = text_of(b.get("content") or "")
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
            elif not since <= ts[:10] <= until:
                continue
            elif name in WRITE_TOOLS:
                if b.get("id") not in errored and is_test(str(inp.get("file_path", ""))):
                    writes.append((ts, o.get("uuid") or f"{path}:{b.get('id')}"))
            elif name == "Bash":
                # A Bash that ran and exited non-zero (a RED pytest after the heredoc) is
                # an error result starting "Exit code N"; its file was written. Any other
                # error (a hook deny, a refused permission) means it never ran.
                err = errored.get(b.get("id"))
                if ((err is None or err.startswith("Exit code"))
                        and any(is_test(p) for p in bash_writes(str(inp.get("command", ""))))):
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
