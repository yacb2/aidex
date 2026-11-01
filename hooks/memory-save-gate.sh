#!/bin/sh
# PreToolUse hook — refuse to let the unrecoverable shapes of non-memory reach disk.
#
# Matches Write/Edit/MultiEdit on ${CLAUDE_CONFIG_DIR:-~/.claude}/projects/*/memory/*.md and ~/.claude/projects/*/memory/*.md,
# MEMORY.md included.
# Anything else is an immediate allow. It does not implement a single check of its own:
# it imports CHECKS from the installed memory-sweep.py, so the gate and the sweep can
# never disagree about what a memory is. If that module moves, breaks, or
# raises, this hook exits 0 and the write proceeds — there is no input on which it can
# prevent work by failing.
#
# ---------------------------------------------------------------------------
# DECISION 2026-10-04 (round 3, R3): the gate BLOCKS only on no-secrets
# ---------------------------------------------------------------------------
# `unpushed-is-not-a-fact` and `index-is-an-index` are advisory here: they still run,
# log ("nudge") and report, and the write proceeds. Why: the 2026-10-04 review found
# 6 blocks since 2026-08-31, all of them the author's own probes, none a real write
# a later audit would have deleted (aidex_ws/.context/research/2026-10-04-memory-save-gate-review.md).
# The sweep (memory-sweep.py) keeps its own BLOCKING tuple for its audit reports; the
# gate's set is GATE_BLOCKING below, deliberately not imported.
# NEXT REVIEW: 2026-11-30 (the sunset review below); if no-secrets alone shows no
# justified block by then, the hook is unwired.
#
# ---------------------------------------------------------------------------
# SUNSET CRITERION — review 2026-11-30, three months from 2026-08-31
# ---------------------------------------------------------------------------
# This repo retired `durability-stop-hook.sh` (now docs/retired/hooks/) on 2026-08-03 after "4 blocks, 0
# justified, 4 misfires". It could retire it because the criterion had been written
# down in advance. A new BLOCKing hook without one repeats the failure the retirement
# was supposed to teach, so:
#
#   A block is JUSTIFIED if the write, had it landed, would have produced a file a
#   later audit deleted or moved. Nothing else counts — not "the check fired", not
#   "the author reworded it". The audit's verdict is the judge.
#
#   Blocks are COUNTED from every config dir's aidex/memory-gate.jsonl (each session logs to
#   ${CLAUDE_CONFIG_DIR:-~/.claude}/aidex/memory-gate.jsonl, so ~/.claude and ~/.claude-work both count): one line per decision,
#   {ts, decision, rules, path}. The DECISION is logged, never the body — a body could
#   contain the secret the hook just blocked.
#
#   RETIREMENT RULE: if justified blocks are under half of all blocks at review, the
#   hard checks demote to NUDGE (as of 2026-10-04 only no-secrets is still hard). Under a tenth, the hook is unwired entirely.
#
# ---------------------------------------------------------------------------
# Protocol, established empirically 2026-08-31 (probe, throwaway project, then deleted)
# ---------------------------------------------------------------------------
#  * The deny reason field is `permissionDecisionReason`, NOT `reason`. With `reason`
#    the model receives the bare string "Hook PreToolUse:Write denied this tool" and
#    has no idea which check fired or how to waive it — an opaque block, which is how
#    a gate earns its retirement. The sibling hook uses `reason` on an ALLOW, where it
#    does not matter; copying that shape here would have been silently wrong.
#  * A hook `deny` DOES win over a `permissionDecision: "allow"` returned earlier in
#    the same matcher block. That mattered because a personal, unshipped sibling,
#    `approve-claude-dir-pretooluse.sh`, allowed every path containing `/.claude/`:
#    the `~/.claude` memory root, though not a `~/.claude-work` one (that substring
#    does not match it). Either way a deny here wins. Verified: same block, allow
#    first, deny second, write refused.
#  * A NUDGE never returns `allow`. It returns `additionalContext` and exits 0, so the
#    write proceeds under whatever permission it would otherwise have had. Returning
#    `allow` would auto-approve writes this hook has no business approving, and would
#    silently loosen permissions if the sibling hook is ever narrowed. The probe
#    confirmed the write lands; it did NOT confirm the text reaches the transcript, so
#    the nudge's logging value is certain and its user-visible value is not.
#
# Edit/MultiEdit carry a fragment, not the resulting file. Reconstructing the post-write
# body would mean reimplementing edit semantics inside a hook that must fail open — a
# bad trade — so only `no-secrets` runs on the incoming text there. Memory files are
# written with Write by design; Edit is the rare path and this is a backstop, not the gate.
#
# Inert until wired in settings.json, as every shipped hook is (install.sh:10).

# The script is captured into a variable and passed with -c, NOT piped or fed as a
# heredoc to `python3 -`: either of those consumes the hook's stdin, which is the event
# JSON this hook exists to read. With -c, stdin reaches Python untouched.
PYSRC=$(cat <<'PY'
import json, os, sys, time

def allow():                       # every failure path lands here
    sys.exit(0)

try:
    raw = sys.stdin.read()
    ev = json.loads(raw)
    tool = ev.get("tool_name") or ""
    ti = ev.get("tool_input") or {}
    path = ti.get("file_path") or ""
except Exception:
    allow()

# Decision 2026-10-04 (R3): the only check that refuses a write. See the header.
GATE_BLOCKING = ("no-secrets",)

if tool not in ("Write", "Edit", "MultiEdit"):
    allow()

cfg = (os.environ.get("CLAUDE_CONFIG_DIR") or "").strip(" \t\n\r\v\f")
# Trimmed of surrounding whitespace; a leading ~ or ~/ is the home directory (never
# ~user, as in the shell hooks); anything still relative means the default, never a
# tree under the cwd.
if cfg == "~" or cfg.startswith("~/"):
    cfg = os.path.expanduser("~") + cfg[1:]
cfg = os.path.normpath(cfg) if os.path.isabs(cfg) else os.path.expanduser("~/.claude")
# Both roots: the config dir's memory, and the personal one a CLAUDE_CONFIG_DIR session
# can still write into. Equal when the variable is unset.
roots = [os.path.join(c, "projects") for c in (cfg, os.path.join(os.path.expanduser("~"), ".claude"))]
# Each spelling also matches through symlinks (/tmp/x vs /private/tmp/x): the roots and
# the written path are resolved too (its directory alone, then the whole path, which
# follows a file link), while the literal spelling is tried first.
roots = list(dict.fromkeys(roots + [os.path.realpath(r) for r in roots]))
try:
    ap = os.path.abspath(os.path.expanduser(path))
    cands = list(dict.fromkeys((ap, os.path.join(os.path.realpath(os.path.dirname(ap)),
                                                 os.path.basename(ap)), os.path.realpath(ap))))
except Exception:
    allow()

def memory_file(a, r):
    # <root>/<slug>/memory/<file>.md — exactly that depth, nothing below it.
    parts = a[len(r) + 1:].split(os.sep) if a.startswith(r + os.sep) else []
    return len(parts) == 3 and parts[1] == "memory" and parts[2].endswith(".md")

# The first spelling that IS a memory file wins, not the first under a root: a literal
# path one level too deep (memory/loop/a.md, loop -> .) may resolve to one.
hit = next(((a, r) for a in cands for r in roots if memory_file(a, r)), None)
if hit is None:
    allow()
ap, memroot = hit
parts = ap[len(memroot) + 1:].split(os.sep)
memdir = os.path.join(memroot, parts[0], "memory")

if tool == "Write":
    body = ti.get("content") or ""
    fragment = False
else:
    if tool == "Edit":
        body = ti.get("new_string") or ""
    else:
        body = "\n".join((e or {}).get("new_string") or "" for e in (ti.get("edits") or []))
    fragment = True

try:
    import importlib.util
    # Resolved from this hook's OWN file location (never the cwd, which the harness
    # sets unpredictably), with $CLAUDE_PLUGIN_ROOT as the fallback. AIDEX_MEMORY_SWEEP
    # overrides it for the test suite, which must exercise the repo copy — the installed
    # one can lag, and on 2026-08-31 it did, which is what fail-open is for.
    here = os.environ.get("AIDEX_HOOK_DIR", "")
    sweep = os.environ.get("AIDEX_MEMORY_SWEEP") or os.path.abspath(
        os.path.join(here, "..", "skills", "aidex", "scripts", "memory-sweep.py"))
    if not os.path.exists(sweep) and os.environ.get("CLAUDE_PLUGIN_ROOT"):
        sweep = os.path.join(os.environ["CLAUDE_PLUGIN_ROOT"],
                             "skills", "aidex", "scripts", "memory-sweep.py")
    spec = importlib.util.spec_from_file_location("memory_sweep", sweep)
    ms = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ms)          # guarded by `if __name__ == "__main__"`
except Exception:
    allow()

try:
    is_index = os.path.basename(ap) == "MEMORY.md"
    waived = ms.WAIVER_RX.search(body) is not None
    siblings = [os.path.join(memdir, f) for f in sorted(os.listdir(memdir))
                if f.endswith(".md") and f != "MEMORY.md"] if os.path.isdir(memdir) else []
    ctx = ms.Ctx(parts[0], memdir, siblings)

    findings = []
    for cid, fn in ms.CHECKS.items():
        if fragment and cid != "no-secrets":
            continue                     # a fragment is not the file; see the header
        if not fragment and cid != "no-secrets" and is_index != (cid in ms.INDEX_ONLY):
            continue                     # no-secrets runs on the index too (BL-891)
        if waived and cid != "no-secrets":
            continue                     # no-secrets is never waivable
        try:
            findings.extend(fn(ap, body, ctx) or [])
        except Exception:
            pass                         # one broken check never decides the write

    hard = [f for f in findings if f.get("rule") in GATE_BLOCKING]
    soft = [f for f in findings if f.get("rule") not in GATE_BLOCKING]
except Exception:
    allow()

def log(decision, rules):
    # The decision, never the body: a body could carry the secret just blocked.
    try:
        d = os.path.join(cfg, "aidex")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "memory-gate.jsonl"), "a") as fh:
            fh.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
                                 "decision": decision, "rules": sorted(set(rules)),
                                 "path": ap}) + "\n")
    except Exception:
        pass

if hard:
    lines = ["This write was refused by the memory save gate — "
             "skills/aidex/references/memory-hygiene.md is the canon.", ""]
    for f in hard:
        lines.append("  [%s] %s" % (f.get("rule"), f.get("detail", "")))
        if f.get("fix") and f.get("fix") != "-":
            lines.append("      fix: %s" % f["fix"])
    lines += ["",
              "Fix the content rather than the wording. If the finding is genuinely "
              "wrong, add this line to the file and write again:",
              "    memory-gate: waived — <reason>",
              "It downgrades every block on this file except no-secrets, which is "
              "never waivable."]
    log("deny", [f.get("rule") for f in hard])
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": "\n".join(lines)}}))
    sys.exit(0)

if soft:
    log("nudge", [f.get("rule") for f in soft])
    msg = "Memory save gate (advisory — the write proceeded): " + "; ".join(
        "[%s] %s" % (f.get("rule"), f.get("detail", "")) for f in soft)
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "additionalContext": msg}}))
sys.exit(0)
PY
)

# This hook's own directory, so the Python above can locate its sibling skills/
# tree without depending on the cwd the harness happens to use.
export AIDEX_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

exec python3 -c "$PYSRC"
