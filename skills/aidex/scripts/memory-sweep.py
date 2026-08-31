#!/usr/bin/env python3
"""memory-sweep.py — audit every Claude Code memory directory against rules/memory-hygiene.md.

READ-ONLY BY CONSTRUCTION. It prints findings and the exact command that would fix each
one; it never deletes, moves or rewrites anything. That is deliberate: memory files are
unversioned and ungitignored-by-nature, so a wrong sweep is unrecoverable (the reason
`.aidex-waivers` was lost on 2026-08-03 was a tool that wrote where it was only asked to
read).

Checks, each keyed to a clause of the rule:

  MEM-LOG    a memory over the word budget — a session log wearing a memory's front-matter
  MEM-TYPE   no `type:` front-matter, so recall cannot classify it
  MEM-TMP    a memory directory under a throwaway project path (/tmp, /private/var/folders)
  MEM-DUP    byte-identical memory directories — a project-path slug collision
  MEM-INDEX  a MEMORY.md index over the always-on budget

Exit 0 when clean, 1 when any finding exists, so a hook or CI step can gate on it.

Usage:
  memory-sweep.py                 # every project
  memory-sweep.py --project aidex # substring match on the project slug
  memory-sweep.py --json out.json
"""
from __future__ import annotations

import argparse
import collections
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

# Overridable so the sweep can be tested against a fixture tree. A checker with no
# adversarial test is the exact pattern the 2026-07-25 audit named ("checkers lie by
# omission"). Until 2026-08-31 this comment claimed a test that did not exist; the
# fixture set is now real, at tests/fixtures/memory/, run by tests/test-memory-sweep.sh.
# AIDEX_MEMORY_PROJECT_ROOT resolves slugs to trees the same way, for the checks that
# read the project.
PROJECTS = os.environ.get("AIDEX_MEMORY_ROOT") or os.path.expanduser("~/.claude/projects")

# Budgets. Both come from rules/memory-hygiene.md — keep them in lockstep with it.
# 800 is the p90 of the 416 memories measured 2026-08-06 (median 277w): it flags the
# tail where session logs actually live without burying it in 113 dense-but-legitimate
# facts, which is what a 400w budget did on the first run.
MEMORY_WORD_BUDGET = 800
INDEX_WORD_BUDGET = 1200

TYPE_RX = re.compile(r"^\s*type:\s*(\S+)", re.M)
TEMP_MARKERS = ("-private-tmp", "-private-var-folders", "-tmp-", "-var-folders")


def words(path: str) -> int:
    try:
        return len(open(path, errors="replace").read().split())
    except OSError:
        return 0


def memory_dirs(filter_sub: str | None) -> list[str]:
    out = []
    for d in sorted(glob.glob(os.path.join(PROJECTS, "*", "memory"))):
        if not os.path.isdir(d):
            continue
        if filter_sub and filter_sub not in d:
            continue
        out.append(d)
    return out


def project_of(path: str) -> str:
    """The project slug a memory dir belongs to (its parent directory's name)."""
    return os.path.basename(os.path.dirname(path.rstrip("/")))


# ---------------------------------------------------------------- content tests
# The five checks above test a memory's SHAPE. These six test what it IS — the rule
# `rules/memory-hygiene.md` states in prose and nothing enforced until 2026-08-31, when
# an adversarial read of 425 memories found nine were memories. Keep the ids in lockstep
# with the rule text; `tests/test-memory-sweep.sh` fails if they drift apart.
#
# One implementation, two consumers: the save-gate hook imports CHECKS rather than
# reimplementing a check in bash.

PROJECT_ROOT_OVERRIDE = os.environ.get("AIDEX_MEMORY_PROJECT_ROOT")

SECRET_RX = (
    re.compile(r"\bsk-[A-Za-z0-9_-]{20,}"),
    re.compile(r"\bre_[A-Za-z0-9_]{20,}"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}"),
    re.compile(r"(?i)\b(?:password|passwd|secret|api[_-]?key|access[_-]?token|bearer)\b"
               r"\s*[:=]\s*[\"']?([A-Za-z0-9_\-/+.]{12,})"),
)
# A memory that documents a credential's SHAPE is not a leak. This is what keeps
# `sk-REDACTED-EXAMPLE` from being treated like a key.
PLACEHOLDER_RX = re.compile(r"(?i)redacted|example|placeholder|xxxx|<[^>]+>|your[_-]|\.\.\.")

# `v2` and `next step` are gone: measured on the fleet they fired on "Vue v2", "/api/v2"
# and "the onboarding flow's next step", which are not deferred work. NEGATION_RX drops
# the other direction — "nothing is pending anymore" is a closure, not a TODO.
PENDING_RX = re.compile(r"(?i)\b(pending|todo|to-do|still open|follow[- ]?ups?"
                        r"|not yet (?:done|implemented)|remains? open)\b")
NEGATION_RX = re.compile(r"(?i)\b(nothing|no longer|never|not|none|stopped being)\b"
                         r"[^.]{0,40}$")
BL_RX = re.compile(r"\bBL-\d{2,}\b")

# 7, 8, 10 and 40 are the conventional short/full SHA lengths. 9 and 11-39 hex inside
# backticks are almost never a commit reference, and matching them turned every hex-ish
# token in the fleet into a "commit that does not exist".
SHA_RX = re.compile(r"`([0-9a-f]{7,8}|[0-9a-f]{10}|[0-9a-f]{40})`"
                    r"|\bcommit\s+([0-9a-f]{7,8}|[0-9a-f]{10}|[0-9a-f]{40})\b")
_SHA_CACHE: dict[tuple[str, str], bool] = {}
_REPO_CACHE: dict[str, list[str]] = {}

BACKTICK_RX = re.compile(r"`([^`\n]+)`")
PATHLIKE_RX = re.compile(r"^[\w./-]+$")
PATH_EXTS = (".py", ".sh", ".md", ".ts", ".tsx", ".js", ".vue", ".json",
             ".yml", ".yaml", ".toml", ".sql", ".cfg", ".ini")

# One index dialect was assumed and 13 of 30 real indexes failed a check that gates a
# write. Bold titles, a colon separator and a bare link are all indexes; what is NOT an
# index is a line carrying prose with no link at all.
INDEX_LINK_RX = re.compile(
    r"^\s*[-*]\s*\*{0,2}\[([^\]]+)\]\(([^)]+)\)\*{0,2}\s*(?:[—–:-]\s*(.*))?$")
INDEX_HOOK_WORDS = 25

FRONTMATTER_RX = re.compile(r"\A---\n.*?\n---\n", re.S)
STOPWORDS = set("the a an and or of to in on is are was were it its this that for with "
                "from as at by be been not no but they them their than then when".split())
TWIN_THRESHOLD = 0.6

_TREE_CACHE: dict[str, set[str] | None] = {}


class Ctx:
    """What a content check needs beyond the file itself."""

    def __init__(self, proj: str, memdir: str, siblings: list[str]):
        self.proj = proj
        self.memdir = memdir
        self.siblings = siblings          # other memory files in the same directory
        self.project_path = project_path_of(proj)


_PATH_CACHE: dict[str, str | None] = {}


def project_path_of(slug: str) -> str | None:
    """The working tree a memory directory's slug refers to, or None if it is gone.

    The slug is the project path with `/`, `_` and a leading `.` all flattened to `-`,
    which is lossy in three directions at once: `echo-lab-ws` may be `echo_lab_ws`,
    `--claude` is `/.claude`, and `bindery-press` really does keep its dash. Decoding it
    by string rules guesses wrong — on 2026-08-31 that resolved
    `-Users-yoelacevedo--claude` to `/Users/yoelacevedo//claude`, an existing but wrong
    directory, and every check that reads the project then reported against it.

    So: walk the real filesystem instead, consuming slug segments greedily against what
    is actually there. A miss returns None, and the checks that need a tree say nothing
    rather than judge against the wrong one.
    """
    if slug in _PATH_CACHE:
        return _PATH_CACHE[slug]
    _PATH_CACHE[slug] = result = _resolve_slug(slug)
    return result


def _resolve_slug(slug: str) -> str | None:
    if PROJECT_ROOT_OVERRIDE:
        p = os.path.join(PROJECT_ROOT_OVERRIDE, slug)
        return p if os.path.isdir(p) else None
    parts = slug.lstrip("-").split("-")
    cur, i = "/", 0
    while i < len(parts):
        try:
            entries = set(os.listdir(cur))
        except OSError:
            return None
        hit = None
        for j in range(len(parts), i, -1):          # longest run of segments first
            for sep in ("-", "_", ""):
                name = sep.join(parts[i:j])
                for cand in (name, "." + name):
                    if cand in entries and os.path.isdir(os.path.join(cur, cand)):
                        hit = (cand, j)
                        break
                if hit:
                    break
            if hit:
                break
        if not hit:
            return None
        cur = os.path.join(cur, hit[0])
        i = hit[1]
    return cur


def _finding(rule: str, ctx: Ctx, path: str, detail: str, fix: str) -> dict:
    return {"rule": rule, "project": ctx.proj, "path": path, "detail": detail, "fix": fix}


def _body_words(body: str) -> set[str]:
    body = FRONTMATTER_RX.sub("", body)
    return {w for w in re.findall(r"[a-z]{4,}", body.lower()) if w not in STOPWORDS}


def _tree_files(root: str) -> set[str] | None:
    """Names under `root`, or None when the tree was too large to enumerate.

    Two defects this shape exists to prevent. Recording only files made every directory
    reference (`_archive/`, `apps/users/`) unmatchable by construction — 321 of 857
    flagged references. And caching a *truncated* walk meant 74% of `~/.claude` was
    permanently invisible while the check still reported absence: an unanswerable
    question was being answered "no". None means "cannot say", and the caller stays
    silent rather than accusing.
    """
    if root in _TREE_CACHE:
        return _TREE_CACHE[root]
    seen: set[str] = set()
    budget = 200000
    truncated = False
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames
                       if d not in (".git", "node_modules", ".venv", "__pycache__",
                                    "dist", ".next", "build", ".mypy_cache")]
        for name in list(dirnames) + filenames:
            full = os.path.join(dirpath, name)
            seen.add(name)
            seen.add(os.path.relpath(full, root))
            budget -= 1
        if budget <= 0:
            truncated = True
            break
    _TREE_CACHE[root] = None if truncated else seen
    return _TREE_CACHE[root]


def _search_roots(body: str, ctx: Ctx) -> list[str]:
    """The project tree, plus any sibling repo the memory names by directory name."""
    if not ctx.project_path:
        return []
    roots = [ctx.project_path]
    parent = os.path.dirname(ctx.project_path.rstrip("/"))
    own = os.path.basename(ctx.project_path.rstrip("/"))
    if os.path.isdir(parent):
        try:
            names = os.listdir(parent)
        except OSError:
            names = []
        for name in names:
            if name == own or name.startswith("."):
                continue
            if os.path.isdir(os.path.join(parent, name)) and \
                    re.search(r"\b" + re.escape(name) + r"\b", body):
                roots.append(os.path.join(parent, name))
    return roots


def _looks_opaque(value: str) -> bool:
    """True only for a value that could actually BE a credential.

    The most common legitimate memory about a secret says *where it lives* —
    `api_key = os.environ.get("RESEND_KEY")`, `password: POSTGRES_PASSWORD_ENV`,
    `token: settings.RESEND_API_KEY`. The first draft read all of those as leaks, and
    no-secrets is the one check that cannot be waived, so a false positive here is
    unresolvable by the person hitting it.
    """
    if len(value) < 16:
        return False
    if "(" in value or ")" in value:
        return False                                   # a call, not a value
    if re.search(r"\.[a-z_]", value):
        return False                                   # attribute access: settings.KEY
    if value.replace("_", "").isupper():
        return False                                   # an env var NAME
    if value.islower() and "_" in value:
        return False                                   # a snake_case identifier
    return bool(re.search(r"[A-Za-z]", value) and re.search(r"[0-9]", value))


def check_no_secrets(path: str, body: str, ctx: Ctx) -> list[dict]:
    for rx in SECRET_RX:
        for m in rx.finditer(body):
            generic = bool(m.groups() and m.group(1))
            token = m.group(1) if generic else m.group(0)
            if PLACEHOLDER_RX.search(token):
                continue
            if generic and not _looks_opaque(token):
                continue
            return [_finding(
                "no-secrets", ctx, path,
                "a credential-shaped token in the body — memories are unversioned "
                "plain text and are read into every session of this project",
                "remove the value, name the store it lives in, and rotate the credential",
            )]
    return []


def check_pending_needs_a_ticket(path: str, body: str, ctx: Ctx) -> list[dict]:
    if BL_RX.search(body):
        return []
    m = next((m for m in PENDING_RX.finditer(body)
              if not NEGATION_RX.search(body[max(0, m.start() - 60):m.start()])), None)
    if not m:
        return []
    return [_finding(
        "pending-needs-a-ticket", ctx, path,
        f"describes work that is not done (\"{m.group(0)}\") with no BL-NNN carrying it "
        f"— pending work is a backlog item, and memory has no way to close it",
        "register the work (register-item.sh) and cite the id, or drop the memory",
    )]


def check_unpushed_is_not_a_fact(path: str, body: str, ctx: Ctx) -> list[dict]:
    roots = [g for r in _search_roots(body, ctx) for g in _git_repos(r)]
    if not roots:
        return []
    out = []
    for m in SHA_RX.finditer(body):
        sha = m.group(1) or m.group(2)
        if _sha_reachable(sha, roots):
            continue
        out.append(_finding(
            "unpushed-is-not-a-fact", ctx, path,
            f"cites commit {sha}, unreachable in " +
            ", ".join(os.path.basename(r) for r in roots) +
            " — it was amended, rebased away, or never left another machine",
            "cite a commit that exists, or state the fact without the SHA",
        ))
    return out


def _git_repos(root: str) -> list[str]:
    """Every git repo at or one level under `root`.

    A `*_ws` project is a split-repo workspace: a `.git` at the root AND one in
    `frontend/`, `backend/`, `frontend_mobile/`. Checking only the root made every
    commit made in a sub-repo look unreachable — 338 of the 373 first-run findings.
    """
    if root in _REPO_CACHE:
        return _REPO_CACHE[root]
    out = []
    if os.path.isdir(os.path.join(root, ".git")):
        out.append(root)
    try:
        for name in sorted(os.listdir(root)):
            sub = os.path.join(root, name)
            if not name.startswith(".") and os.path.isdir(os.path.join(sub, ".git")):
                out.append(sub)
    except OSError:
        pass
    _REPO_CACHE[root] = out
    return out


def _sha_reachable(sha: str, roots: list[str]) -> bool:
    """True if the SHA resolves in any repo the memory could plausibly mean.

    Cross-repo memories are normal — one memory in `aidex` legitimately cites commits in
    loom, lexis and ph. Checking only the memory's own project made 374 of 429 memories
    look like they cited phantom commits.
    """
    for r in roots:
        key = (r, sha)
        if key not in _SHA_CACHE:
            try:
                # `cat-file -e` only proves the object is in the database, and an
                # amended commit survives there until gc — so the check stayed silent on
                # its own stated primary case. Reachability from a ref is the question.
                _SHA_CACHE[key] = (
                    subprocess.run(["git", "-C", r, "cat-file", "-e", sha + "^{commit}"],
                                   capture_output=True, timeout=10).returncode == 0
                    and bool(subprocess.run(
                        ["git", "-C", r, "for-each-ref", "--contains", sha,
                         "--count=1", "--format=%(refname)"],
                        capture_output=True, timeout=30).stdout.strip()))
            except (OSError, subprocess.SubprocessError):
                _SHA_CACHE[key] = True        # cannot verify: never accuse
        if _SHA_CACHE[key]:
            return True
    return False


def check_twin_exists(path: str, body: str, ctx: Ctx) -> list[dict]:
    mine = _body_words(body)
    if len(mine) < 8:
        return []
    candidates = [(s, None) for s in ctx.siblings if s != path]
    if ctx.project_path:
        cm = os.path.join(ctx.project_path, "CLAUDE.md")
        if os.path.isfile(cm):
            candidates.append((cm, None))
    for other, _ in candidates:
        try:
            theirs = _body_words(open(other, errors="replace").read())
        except OSError:
            continue
        if not theirs:
            continue
        j = len(mine & theirs) / len(mine | theirs)
        if j >= TWIN_THRESHOLD:
            if os.path.basename(other) < os.path.basename(path):
                return []          # the pair is reported once, from its first member
            return [_finding(
                "twin-exists", ctx, path,
                f"{int(j * 100)}% of its content words are shared with "
                f"{os.path.basename(other)} — the same fact, saved twice",
                f"keep one; if both are wanted, link them with [[name]] instead",
            )]
    return []


def check_named_thing_exists(path: str, body: str, ctx: Ctx) -> list[dict]:
    roots = _search_roots(body, ctx)
    trees = {r: _tree_files(r) for r in roots}
    roots = [r for r in roots if trees[r] is not None]     # never accuse from a partial walk
    if not roots:
        return []
    missing = []
    for tok in BACKTICK_RX.findall(body):
        tok = tok.strip().rstrip("/")
        if not tok or not PATHLIKE_RX.match(tok):
            continue
        if tok.startswith("/"):
            continue          # `/code-review`, `/api/v2` — a slash-command or a route
        if "/" not in tok and not tok.endswith(PATH_EXTS):
            continue
        if any(os.path.exists(os.path.join(r, tok)) or tok in trees[r] or
               os.path.basename(tok) in trees[r] for r in roots):
            continue
        missing.append(tok)
    if not missing:
        return []
    return [_finding(
        "named-thing-exists", ctx, path,
        f"names {', '.join(sorted(set(missing))[:6])}, absent from " +
        ", ".join(os.path.basename(r) for r in roots) +
        " — a memory pointing at something gone describes a project that no longer exists",
        "re-read the memory: if its subject is gone, so is the memory",
    )]


def check_index_is_an_index(path: str, body: str, ctx: Ctx) -> list[dict]:
    """One finding per index, carrying the count.

    Reported per line, a MEMORY.md that is a whole document rather than an index emitted
    60 identical findings and buried everything else. The count is kept in the detail so
    a consumer can still assert "zero content-carrying lines" rather than "zero
    findings" — a partly-bad index and a wholly-bad one must not look the same.
    """
    if os.path.basename(path) != "MEMORY.md":
        return []
    bad_shape, long_hook, total = [], [], 0
    in_comment = False
    for n, line in enumerate(body.splitlines(), 1):
        s = line.strip()
        if in_comment:                       # only the OPENING line was skipped before
            in_comment = "-->" not in s
            continue
        if s.startswith("<!--"):
            in_comment = "-->" not in s
            continue
        if not s or s.startswith("#") or set(s) <= set("-*_ "):   # blank, heading, rule
            continue
        total += 1
        m = INDEX_LINK_RX.match(s)
        if not m:
            bad_shape.append(n)
            continue
        hook = (m.group(3) or "").split()
        if len(hook) > INDEX_HOOK_WORDS:
            long_hook.append(n)
    if not bad_shape and not long_hook:
        return []
    bits = []
    if bad_shape:
        bits.append(f"{len(bad_shape)} of {total} lines are not "
                    f"`- [Title](file.md) — hook` (first: line {bad_shape[0]})")
    if long_hook:
        bits.append(f"{len(long_hook)} hook(s) over {INDEX_HOOK_WORDS}w "
                    f"(first: line {long_hook[0]})")
    return [_finding(
        "index-is-an-index", ctx, path,
        "; ".join(bits) + " — the index is always-on, so a line carrying content is "
        "paid for in every session of this project",
        "move the content into its memory file; leave a one-line hook",
    )]


CHECKS = {
    "no-secrets": check_no_secrets,
    "pending-needs-a-ticket": check_pending_needs_a_ticket,
    "unpushed-is-not-a-fact": check_unpushed_is_not_a_fact,
    "twin-exists": check_twin_exists,
    "named-thing-exists": check_named_thing_exists,
    "index-is-an-index": check_index_is_an_index,
}

# Reported, never a verdict on its own: 800w says "probably a session log", it does not
# say "delete this". The content tests above are what decide.
SIGNALS = ("MEM-LOG",)

# twin-exists is NOT blocking. Measured 2026-08-31 against the 148 DELETE-DUP verdicts
# the readers produced: only 3 were memory-vs-memory pairs at all, and those scored
# 0.11-0.27 Jaccard. A lexical score cannot reproduce semantic duplication, so this
# check keeps a high threshold and only ever advises — reading is the agent's job.
# pending-needs-a-ticket is advisory, not blocking: measured on 429 real memories it
# fires on 21% of them, and the review reproduced false positives inside negations and
# on version strings. A gate at that rate teaches people to bypass it.
BLOCKING = ("no-secrets", "unpushed-is-not-a-fact", "index-is-an-index")
ADVISORY = ("named-thing-exists", "twin-exists", "pending-needs-a-ticket")
WAIVER_RX = re.compile(r"^\s*memory-gate:\s*waived\s*[—-]\s*\S", re.M)


INDEX_ONLY = ("index-is-an-index",)


def run_checks(path: str, body: str, ctx: Ctx) -> list[dict]:
    """The rule states it: the first five run per memory file, the last on the index.

    Running the per-memory checks over MEMORY.md judged an index of one-line hooks as if
    it were a memory — 6 pending and 11 named-thing findings on indexes alone.
    """
    is_index = os.path.basename(path) == "MEMORY.md"
    # A waiver line in the file downgrades everything but no-secrets, which is never
    # waivable. The rule documented this mechanism before anything implemented it.
    waived = WAIVER_RX.search(body) is not None
    out = []
    for cid, fn in CHECKS.items():
        if is_index != (cid in INDEX_ONLY):
            continue
        if waived and cid != "no-secrets":
            continue
        try:
            out.extend(fn(path, body, ctx))
        except Exception as exc:                      # a check must never break the sweep
            out.append({"rule": cid, "project": ctx.proj, "path": path,
                        "detail": f"check errored: {exc}", "fix": "-"})
    return out



def sweep(dirs: list[str]) -> list[dict]:
    findings: list[dict] = []
    by_digest: dict[str, list[str]] = collections.defaultdict(list)

    for d in dirs:
        proj = project_of(d)

        if any(m in proj for m in TEMP_MARKERS):
            findings.append({
                "rule": "MEM-TMP", "project": proj, "path": d,
                "detail": "memory directory under a throwaway project path — the harness "
                          "wrote it, no session will ever read it",
                "fix": f'rm -rf "{d}"',
            })

        files = sorted(glob.glob(os.path.join(d, "*.md")))
        memories = [f for f in files if os.path.basename(f) != "MEMORY.md"]
        ctx = Ctx(proj, d, memories)
        digest = hashlib.sha256()
        for f in files:
            if os.path.basename(f) == "MEMORY.md":
                findings.extend(run_checks(f, open(f, errors="replace").read(), ctx))
                continue
            with open(f, "rb") as fh:
                digest.update(fh.read())
            w = words(f)
            body = open(f, errors="replace").read()
            if w > MEMORY_WORD_BUDGET:
                findings.append({
                    "rule": "MEM-LOG", "project": proj, "path": f,
                    "detail": f"{w}w (budget {MEMORY_WORD_BUDGET}) — read it: if it narrates "
                              f"a run, it belongs in .context/, not memory",
                    "fix": "split into one-fact files, or move the narrative to .context/",
                })
            if not TYPE_RX.search(body):
                findings.append({
                    "rule": "MEM-TYPE", "project": proj, "path": f,
                    "detail": "no `type:` front-matter (user | feedback | project | reference)",
                    "fix": "add a type: line to the front-matter",
                })
            findings.extend(run_checks(f, body, ctx))
        if files:
            by_digest[digest.hexdigest()].append(d)

        index = os.path.join(d, "MEMORY.md")
        if os.path.isfile(index):
            iw = words(index)
            if iw > INDEX_WORD_BUDGET:
                findings.append({
                    "rule": "MEM-INDEX", "project": proj, "path": index,
                    "detail": f"{iw}w always-on (budget {INDEX_WORD_BUDGET}) — every line is "
                              f"paid for in every session of this project",
                    "fix": "shorten hooks to one line each; drop entries whose work has closed",
                })

    for group in by_digest.values():
        if len(group) > 1:
            findings.append({
                "rule": "MEM-DUP", "project": project_of(group[0]),
                "path": ", ".join(project_of(g) for g in group),
                "detail": f"{len(group)} byte-identical memory directories — a project-path "
                          f"slug collision, not {len(group)} projects",
                "fix": "keep the directory whose project path still exists; remove the others",
            })

    return findings


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", help="substring match on the project slug")
    ap.add_argument("--json", help="write findings to this path as JSON")
    args = ap.parse_args()

    dirs = memory_dirs(args.project)
    findings = sweep(dirs)

    total_files = sum(
        1 for d in dirs for f in glob.glob(os.path.join(d, "*.md"))
        if os.path.basename(f) != "MEMORY.md"
    )
    print(f"{len(dirs)} memory director{'y' if len(dirs) == 1 else 'ies'} · "
          f"{total_files} memories", flush=True)

    if args.json:
        with open(args.json, "w") as fh:
            json.dump({"dirs": len(dirs), "memories": total_files,
                       "findings": findings}, fh, indent=1)

    if not findings:
        print("clean — nothing over budget, every memory typed, no throwaway or duplicate dirs")
        return 0

    by_rule = collections.defaultdict(list)
    for f in findings:
        by_rule[f["rule"]].append(f)
    for rule in BLOCKING + ADVISORY + ("MEM-TMP", "MEM-DUP", "MEM-INDEX", "MEM-LOG", "MEM-TYPE"):
        rows = by_rule.get(rule)
        if not rows:
            continue
        print(f"\n[{rule}] {len(rows)}")
        for r in rows:
            print(f"  {r['project']}")
            print(f"    {r['path']}")
            print(f"    {r['detail']}")
            print(f"    fix: {r['fix']}")

    print(f"\n{len(findings)} finding(s). Nothing was changed — this sweep only reports.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
