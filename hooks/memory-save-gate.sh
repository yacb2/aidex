#!/bin/sh
# PreToolUse hook — refuse to let the unrecoverable shapes of non-memory reach disk.
#
# Matches Write/Edit/MultiEdit on ~/.claude/projects/*/memory/*.md, MEMORY.md included.
# Anything else is an immediate allow. It does not implement a single check of its own:
# it imports CHECKS and BLOCKING from the installed memory-sweep.py, so the gate and the
# sweep can never disagree about what a memory is. If that module moves, breaks, or
# raises, this hook exits 0 and the write proceeds — there is no input on which it can
# prevent work by failing.
#
# ---------------------------------------------------------------------------
# SUNSET CRITERION — review 2026-11-30, three months from 2026-08-31
# ---------------------------------------------------------------------------
# This repo retired `durability-stop-hook.sh` on 2026-08-03 after "4 blocks, 0
# justified, 4 misfires". It could retire it because the criterion had been written
# down in advance. A new BLOCKing hook without one repeats the failure the retirement
# was supposed to teach, so:
#
#   A block is JUSTIFIED if the write, had it landed, would have produced a file a
#   later audit deleted or moved. Nothing else counts — not "the check fired", not
#   "the author reworded it". The audit's verdict is the judge.
#
#   Blocks are COUNTED from ~/.claude/aidex/memory-gate.jsonl: one line per decision,
#   {ts, decision, rules, path}. The DECISION is logged, never the body — a body could
#   contain the secret the hook just blocked.
#
#   RETIREMENT RULE: if justified blocks are under half of all blocks at review, the
#   hard checks demote to NUDGE. Under a tenth, the hook is unwired entirely.
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
#    the same matcher block. That matters because `approve-claude-dir-pretooluse.sh`
#    already matches `/.claude/` — which is every path this gate guards — and allows
#    it. Verified: same block, allow first, deny second, write refused.
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

if tool not in ("Write", "Edit", "MultiEdit"):
    allow()

home = os.path.expanduser("~")
memroot = os.path.join(home, ".claude", "projects")
try:
    ap = os.path.abspath(os.path.expanduser(path))
except Exception:
    allow()
# ~/.claude/projects/<slug>/memory/<file>.md — exactly that depth, nothing below it.
parts = ap[len(memroot) + 1:].split(os.sep) if ap.startswith(memroot + os.sep) else []
if len(parts) != 3 or parts[1] != "memory" or not parts[2].endswith(".md"):
    allow()
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
    # The ABSOLUTE installed path, never a relative traversal from this hook's own
    # directory: the harness invokes hooks with an unpredictable cwd. AIDEX_MEMORY_SWEEP
    # overrides it for the test suite, which must exercise the repo copy — the installed
    # one can lag, and on 2026-08-31 it did, which is what fail-open is for.
    sweep = os.environ.get("AIDEX_MEMORY_SWEEP") or os.path.join(
        home, ".claude", "skills", "aidex", "scripts", "memory-sweep.py")
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
        if not fragment and is_index != (cid in ms.INDEX_ONLY):
            continue
        if waived and cid != "no-secrets":
            continue                     # no-secrets is never waivable
        try:
            findings.extend(fn(ap, body, ctx) or [])
        except Exception:
            pass                         # one broken check never decides the write

    hard = [f for f in findings if f.get("rule") in ms.BLOCKING]
    soft = [f for f in findings if f.get("rule") not in ms.BLOCKING]
except Exception:
    allow()

def log(decision, rules):
    # The decision, never the body: a body could carry the secret just blocked.
    try:
        d = os.path.join(home, ".claude", "aidex")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "memory-gate.jsonl"), "a") as fh:
            fh.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
                                 "decision": decision, "rules": sorted(set(rules)),
                                 "path": ap}) + "\n")
    except Exception:
        pass

if hard:
    lines = ["This write was refused by the memory save gate — "
             "rules/memory-hygiene.md is the canon.", ""]
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

exec python3 -c "$PYSRC"
