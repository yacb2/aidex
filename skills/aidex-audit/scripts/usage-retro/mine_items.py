#!/usr/bin/env python3
"""
mine_items.py — join .context/ tracked items (backlog + plans) to the transcript
sessions that actually WORKED on them, and measure per-item execution cost.

Attribution is provenance-gated: an item counts as "touched" by a session only when
its slug/ID appears in a REAL USER PROMPT, an ASSISTANT TEXT, or a TOOL_USE INPUT
(file_path / command / prompt). Appearances inside tool_result payloads are ignored,
because backlog/00-index.md lists every item and would otherwise attribute the whole
register to any session that read the index.

Read-only. Writes items.jsonl + spans.jsonl to the output dir.

WHAT THIS ANSWERS, AND WHAT IT CANNOT
See `references/07-usage-retro.md`. In short: it answers "what did item X cost, in
edits / sessions / user turns / test runs", and it cannot answer wall-clock, thinking
time, or any work done outside a tracked item.

ROOTS ARE PARAMETERS, AND THE PROJECTS ROOT HAS NO DEFAULT
`~/.claude/projects` is where Claude Code puts transcripts for everyone, so defaulting
it is sound. The workspace root is per-machine — there is no layout to guess — so it is
**required**, via `--projects-root` or `AIDEX_PROJECTS_ROOT`. A guessed default would
silently mine the wrong tree, or nothing, and report either as a result.

They are parameters for a second reason too: a fixture corpus is impossible to build
against a hardcoded home directory, so the tests that pin the two invariants below
exist only because of this.
"""
import os, re, sys, glob, json, datetime, argparse, collections
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prompt_kinds

PROJ_ROOT = os.environ.get("AIDEX_PROJECTS_ROOT") or ""
TX_ROOT   = os.environ.get("CLAUDE_PROJECTS_ROOT") or os.path.expanduser("~/.claude/projects")


def add_root_args(ap):
    """Shared flags, so every consumer of this module exposes the same two."""
    ap.add_argument("--projects-root", default="",
                    help="workspace root holding <project>/.context/ — REQUIRED unless "
                         "AIDEX_PROJECTS_ROOT is set (no default: layouts are per-machine)")
    ap.add_argument("--transcripts-root", default="",
                    help=f"Claude Code transcript root (default: {TX_ROOT})")


def require_projects_root():
    """Refuse to run rootless. Reading an unset root as `""` would glob `/*/` and
    mine whatever happens to be there — a wrong answer that looks like an answer."""
    if not PROJ_ROOT:
        sys.exit("ERROR: no projects root. Pass --projects-root <dir> or set "
                 "AIDEX_PROJECTS_ROOT.\nThere is deliberately no default: the workspace "
                 "layout is per-machine, and guessing\none mines the wrong tree (or "
                 "nothing) and reports it as a result.")


def configure(args):
    """Apply parsed root flags. Call once, before build_registry()/tx_dirs_for()."""
    global PROJ_ROOT, TX_ROOT
    if getattr(args, "projects_root", ""):
        PROJ_ROOT = os.path.abspath(os.path.expanduser(args.projects_root))
    if getattr(args, "transcripts_root", ""):
        TX_ROOT = os.path.abspath(os.path.expanduser(args.transcripts_root))
    require_projects_root()

FM = re.compile(r'^---\n(.*?)\n---', re.S)
BL = re.compile(r'\bBL-\d{3}\b')
TOKEN = re.compile(r'\bBL-\d{3}\b|\b20\d\d-\d\d-\d\d-[a-z0-9][a-z0-9-]{2,70}\b')

REVERT = re.compile(r'git\s+(checkout\s+--|revert|reset\s+--hard|stash|restore)')
TESTCMD = re.compile(r'\b(pytest|vitest|npm test|pnpm test|playwright|jest|manage\.py test|test-e2e)')


def parse_fm(path):
    try:
        txt = open(path, errors='replace').read()
    except OSError:
        return None, ""
    m = FM.match(txt)
    if not m:
        return {}, txt
    fm = {}
    for line in m.group(1).split("\n"):
        if ":" in line and not line.startswith((" ", "-", "\t")):
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip().strip('"').strip("'")
    return fm, txt


def build_registry():
    """One record per tracked item: slug, id, project, kind, front-matter, body stats."""
    require_projects_root()   # also guards importers that never call configure()
    items = []
    for pdir in sorted(glob.glob(PROJ_ROOT + "/*/")):
        proj = os.path.basename(pdir.rstrip("/"))
        ctx = os.path.join(pdir, ".context")
        if not os.path.isdir(ctx):
            continue
        specs = []
        for kind, pats in (("backlog", ["backlog/*.md", "backlog/_archive/*.md",
                                        "backlog/_deferred/*.md"]),
                           ("plan", ["plans/*.md", "plans/_archive/*.md",
                                     "plans/*/00-index.md", "plans/_archive/*/00-index.md"])):
            for pat in pats:
                for f in glob.glob(os.path.join(ctx, pat)):
                    specs.append((kind, f))
        for kind, f in specs:
            base = os.path.basename(f)
            if base.startswith("00-index") and kind == "backlog":
                continue
            slug = os.path.basename(os.path.dirname(f)) if base == "00-index.md" else base[:-3]
            if not re.match(r'^20\d\d-\d\d-\d\d-', slug):
                continue
            fm, body = parse_fm(f)
            if fm is None:
                continue
            items.append({
                "project": proj, "kind": kind, "slug": slug, "path": f,
                "id": fm.get("id", ""), "title": fm.get("title", ""),
                "status": fm.get("status", ""), "priority": fm.get("priority", ""),
                # `estimate` is carried so the calibration read (BL-131) can score it
                # against realized effort without re-parsing every item's front-matter.
                "estimate": fm.get("estimate", ""),
                "created": fm.get("created", "") or fm.get("date-added", ""),
                "updated": fm.get("updated", ""),
                "date_added": fm.get("date-added", ""),
                "date_shipped": fm.get("date-shipped", ""),
                "spec_words": len(body.split()),
                "spec_headings": len(re.findall(r'^#{2,3} ', body, re.M)),
                "spec_checkboxes": len(re.findall(r'^\s*- \[[ x]\]', body, re.M)),
                "spec_codeblocks": body.count("```") // 2,
                "spec_filerefs": len(set(re.findall(r'[\w/\.-]+\.(?:py|ts|tsx|vue|js|md|sh|json)\b', body))),
            })
    return items


def tx_dirs_for(proj):
    """Transcript dirs belonging to a project (root + subdir sessions)."""
    a = proj.replace("_", "-")
    out = []
    for d in glob.glob(TX_ROOT + "/*/"):
        n = os.path.basename(d.rstrip("/"))
        core = n.replace("-Users-yoelacevedo-Documents-projects-", "")
        if core == proj or core == a or core.startswith(proj + "-") or core.startswith(a + "-"):
            out.append(d)
    return out


MACHINE_PROMPTS = collections.Counter()


def user_text(o):
    """Text a HUMAN typed, or None.

    Attribution is the whole point of this miner: an item mentioned only by
    machine-authored text was not something the user asked for. This delegates
    to the shared predicate rather than restating it — the local copy used to
    accept any non-`<` string, so SDK harness prompts and expanded skill bodies
    attributed items to the user. Excluded records are counted, not just
    dropped, and main() reports the total.
    """
    kind, text = prompt_kinds.classify(o)
    if kind in prompt_kinds.HUMAN_KINDS:
        return text
    if kind in prompt_kinds.MACHINE_KINDS:
        MACHINE_PROMPTS[kind] += 1
    return None


def assistant_parts(o):
    """(text, [(tool_name, searchable_input, file_path)])"""
    txt, tools = [], []
    for b in o.get("message", {}).get("content", []):
        if not isinstance(b, dict):
            continue
        if b.get("type") == "text":
            txt.append(b.get("text", ""))
        elif b.get("type") == "tool_use":
            inp = b.get("input", {}) or {}
            fp = inp.get("file_path") or inp.get("path") or ""
            searchable = " ".join(str(inp.get(k, "")) for k in
                                  ("file_path", "path", "command", "prompt", "pattern",
                                   "skill", "description", "old_string", "new_string"))
            tools.append((b.get("name", ""), searchable, fp, inp.get("command", "")))
    return "\n".join(txt), tools


def is_working_span(span):
    """The strict-span rule: a span is a WORKING session only if a user prompt named
    the item, or it carries >=3 edits.

    This is the second load-bearing invariant (BL-132) and it is distinct from
    `--min-mentions`, which decides whether a span is EMITTED at all. Without this
    rule "sessions per item" inflates ~2x, and 65% of the low-edit spans have no user
    turn in them at all — an artifact that produced, and then killed, a "half your
    sessions are re-orientation" claim in the 2026-08-07 study.

    It is a per-span FIELD rather than a filter flag, deliberately: the raw span
    survives for anything that wants it, and a consumer cannot pick the wrong
    denominator by forgetting a flag. Same producer-classifies / consumer-reads shape
    as `flagged` in defect-prone.jsonl.
    """
    return bool(span.get("prompt_mentions", 0) >= 1 or span.get("edits", 0) >= 3)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=".")
    ap.add_argument("--min-mentions", type=int, default=2,
                    help="attributed mentions required for a session to count as WORK")
    add_root_args(ap)
    args = ap.parse_args()
    configure(args)

    items = build_registry()
    by_proj = defaultdict(list)
    for it in items:
        by_proj[it["project"]].append(it)
    print(f"registry: {len(items)} tracked items across {len(by_proj)} projects")

    spans = []
    n_unparseable = 0
    for proj, its in sorted(by_proj.items()):
        # slug -> item ; id -> item (ids are project-scoped)
        slug_map = {it["slug"]: it for it in its}
        id_map = {it["id"]: it for it in its if re.match(r'^BL-\d{3}$', it["id"] or "")}
        keys = set(slug_map) | set(id_map)
        if not keys:
            continue

        # One generic token regex (fast) + set intersection, instead of a 400-branch
        # alternation, which is quadratic-ish on multi-hundred-MB transcripts.
        def hits_in(s):
            return {t for t in TOKEN.findall(s) if t in keys}

        files = [f for d in tx_dirs_for(proj) for f in glob.glob(d + "*.jsonl")]
        for f in files:
            try:
                raw = open(f, errors='replace').read()
            except OSError:
                continue
            if not hits_in(raw):
                continue
            # Per line. This was a list comprehension inside
            # `except Exception: continue`, so one malformed line discarded the
            # whole session — including the sessions that just PASSED the
            # `hits_in(raw)` token pre-filter, i.e. exactly the ones known to
            # mention a tracked item. Every sibling reader in this package skips
            # only the bad record; this one disagreed with all of them, and the
            # effect was an item's mention and span counts silently omitting whole
            # sessions with no diagnostic output.
            objs = []
            for l in raw.splitlines():
                if not l.strip():
                    continue
                try:
                    objs.append(json.loads(l))
                except ValueError:
                    n_unparseable += 1

            # per-item accumulators for this session
            acc = defaultdict(lambda: {
                "mentions": 0, "prompt_mentions": 0, "user_turns": 0, "tool_calls": 0,
                "edits": 0, "files": defaultdict(int), "reverts": 0, "test_runs": 0,
                "errors": 0, "skills": [], "first": None, "last": None,
                "prompts": [], "first_idx": None, "last_idx": None,
            })
            timeline = []   # (idx, ts, kind, hits, payload)
            for i, o in enumerate(objs):
                ts = o.get("timestamp", "")
                if o.get("type") == "user":
                    t = user_text(o)
                    if t is None:
                        # tool_result: harvest error flag only, no attribution
                        c = o.get("message", {}).get("content")
                        iserr = isinstance(c, list) and any(
                            isinstance(x, dict) and x.get("type") == "tool_result"
                            and x.get("is_error") for x in c)
                        timeline.append((i, ts, "result", set(), {"err": iserr}))
                        continue
                    hits = hits_in(t)
                    timeline.append((i, ts, "prompt", hits, {"text": t}))
                elif o.get("type") == "assistant":
                    txt, tools = assistant_parts(o)
                    hits = hits_in(txt)
                    for name, searchable, fp, cmd in tools:
                        hits |= hits_in(searchable)
                    timeline.append((i, ts, "assistant", hits, {"tools": tools}))

            # forward-fill attribution: an item stays "active" until another item is
            # mentioned or 40 messages pass with no mention (session drifts elsewhere)
            active, since = None, 0
            for i, ts, kind, hits, pay in timeline:
                if hits:
                    # pick the most specific hit (slug beats id)
                    h = sorted(hits, key=lambda x: (-len(x), x))[0]
                    it = slug_map.get(h) or id_map.get(h)
                    if it:
                        active, since = it["slug"], 0
                        a = acc[active]
                        a["mentions"] += len(hits)
                        if kind == "prompt":
                            a["prompt_mentions"] += 1
                else:
                    since += 1
                    if since > 40:
                        active = None
                if not active:
                    continue
                a = acc[active]
                if a["first"] is None:
                    a["first"], a["first_idx"] = ts, i
                a["last"], a["last_idx"] = ts, i
                if kind == "prompt":
                    a["user_turns"] += 1
                    a["prompts"].append(pay["text"][:400])
                elif kind == "result":
                    if pay["err"]:
                        a["errors"] += 1
                elif kind == "assistant":
                    for name, searchable, fp, cmd in pay["tools"]:
                        a["tool_calls"] += 1
                        if name in ("Edit", "Write", "NotebookEdit"):
                            a["edits"] += 1
                            if fp:
                                a["files"][fp] += 1
                        if name == "Skill":
                            a["skills"].append(searchable.strip().split()[-1] if searchable.strip() else "")
                        if cmd:
                            if REVERT.search(cmd):
                                a["reverts"] += 1
                            if TESTCMD.search(cmd):
                                a["test_runs"] += 1

            for slug, a in acc.items():
                if a["mentions"] < args.min_mentions:
                    continue
                it = slug_map[slug]
                churn = sorted(a["files"].values(), reverse=True)
                span = {
                    "project": proj, "slug": slug, "kind": it["kind"], "id": it["id"],
                    "session": os.path.basename(f), "first": a["first"], "last": a["last"],
                    "mentions": a["mentions"], "prompt_mentions": a["prompt_mentions"],
                    "user_turns": a["user_turns"], "tool_calls": a["tool_calls"],
                    "edits": a["edits"], "distinct_files": len(a["files"]),
                    "max_file_churn": churn[0] if churn else 0,
                    "refile_edits": sum(c - 1 for c in churn if c > 1),
                    "reverts": a["reverts"], "test_runs": a["test_runs"],
                    "errors": a["errors"],
                    "skills": sorted(set(s for s in a["skills"] if s)),
                    "prompts": a["prompts"][:40],
                }
                span["working"] = is_working_span(span)
                spans.append(span)
        print(f"  {proj}: {len([s for s in spans if s['project']==proj])} spans")

    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "items.jsonl"), "w") as fh:
        for it in items:
            fh.write(json.dumps(it, ensure_ascii=False) + "\n")
    with open(os.path.join(args.out, "spans.jsonl"), "w") as fh:
        for s in spans:
            fh.write(json.dumps(s, ensure_ascii=False) + "\n")
    working = sum(1 for s in spans if s["working"])
    print(f"\nwrote {len(items)} items, {len(spans)} spans "
          f"({working} working, {len(spans) - working} below the strict-span rule) "
          f"-> {args.out}")
    if n_unparseable:
        print(f"skipped {n_unparseable} unparseable line(s) — the line only, never "
              f"the session")
    if MACHINE_PROMPTS:
        excluded = ", ".join(f"{n} {k}" for k, n in MACHINE_PROMPTS.most_common())
        print(f"excluded from attribution: {excluded} "
              f"(machine-authored records delivered through the user channel)")


if __name__ == "__main__":
    main()
