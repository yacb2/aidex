#!/usr/bin/env python3
"""Test suite for context-depth-nudge.sh.

Self-contained: builds synthetic transcripts rather than depending on real ones,
so it runs anywhere and does not rot when transcripts are cleaned up.

  python3 ~/.claude/hooks/test-context-depth-nudge.py
"""
import json, os, subprocess, sys, tempfile

HOOK = os.path.expanduser("~/.claude/hooks/context-depth-nudge.sh")
ENV = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin", "HOME": os.path.expanduser("~")}
STATE = os.path.expanduser("~/.claude/tmp")
TMP = tempfile.mkdtemp(prefix="ctxdepth-test-")

fails = []


def check(name, ok, detail=""):
    print(("  PASS  " if ok else "  FAIL  ") + name + (("   <- " + str(detail)[:120]) if detail and not ok else ""))
    if not ok:
        fails.append(name)


def transcript(name, *turns):
    """turns: each is either an int (single-iteration depth) or a list of ints
    (per-iteration depths, to exercise the max-over-iterations rule)."""
    path = os.path.join(TMP, name + ".jsonl")
    with open(path, "w") as f:
        f.write(json.dumps({"type": "user", "message": {"role": "user", "content": "hi"}}) + "\n")
        for t in turns:
            iters = t if isinstance(t, list) else None
            if iters:
                usage = {
                    "input_tokens": 2,
                    "cache_read_input_tokens": sum(iters),   # top-level SUMS iterations
                    "cache_creation_input_tokens": 0,
                    "output_tokens": 100,
                    "iterations": [{"cache_read_input_tokens": d, "cache_creation_input_tokens": 0,
                                    "input_tokens": 0, "output_tokens": 50} for d in iters],
                }
            else:
                usage = {"input_tokens": 2, "cache_read_input_tokens": t - 2,
                         "cache_creation_input_tokens": 0, "output_tokens": 100}
            f.write(json.dumps({"type": "assistant", "message": {
                "role": "assistant", "model": "claude-opus-5", "usage": usage,
                "content": [{"type": "text", "text": "ok"}]}}) + "\n")
    return path


def clean(sid):
    f = os.path.join(STATE, "ctx-band-" + sid)
    if os.path.exists(f):
        os.remove(f)


def run(payload, raw=None):
    data = raw if raw is not None else json.dumps(payload)
    p = subprocess.run(["/bin/sh", HOOK], input=data, capture_output=True, text=True, env=ENV, timeout=30)
    return p.stdout.strip(), p.stderr.strip(), p.returncode


def fire(path, sid):
    out, err, rc = run({"transcript_path": path, "session_id": sid, "prompt": "x"})
    if rc != 0 or err:
        return f"ERROR rc={rc} err={err[:80]}"
    if not out:
        return "SILENT"
    try:
        return json.loads(out)["hookSpecificOutput"]["additionalContext"]
    except Exception as e:
        return f"MALFORMED {e}: {out[:80]}"


print("=== 1. band boundaries are exact ===")
for depth, expect in [(199_999, "SILENT"), (200_000, "1.4x slower"),
                      (249_999, "1.4x slower"), (250_000, "stops paying for itself"),
                      # Band 3's marker is its cost statement, not a recommendation:
                      # the wording that told the assistant what to decide is gone.
                      (299_999, "stops paying for itself"),
                      (300_000, "Over half of all input spend"),
                      (900_000, "Over half of all input spend")]:
    sid = f"TEST-b{depth}"
    clean(sid)
    got = fire(transcript(f"t{depth}", depth), sid)
    check(f"{depth:>9,} -> {expect}", (got == "SILENT") if expect == "SILENT" else (expect in got), got)
    clean(sid)

print("\n=== 2. depth is max-over-iterations, not the billed sum ===")
# Three iterations of 100k each: top-level cache_read reports 300k, real depth is 100k.
# Using the billed sum would fire the RED band at 100k of actual occupancy.
sid = "TEST-iter"
clean(sid)
got = fire(transcript("iter", [100_000, 100_000, 100_000]), sid)
check("3x100k iterations stays silent (real depth 100k)", got == "SILENT", got)
clean(sid)
got = fire(transcript("iter2", [260_000, 260_000]), sid)
check("2x260k iterations fires orange (real depth 260k)", "stops paying for itself" in got, got)
clean(sid)

print("\n=== 3. reads the LAST turn, not the deepest ===")
sid = "TEST-last"
clean(sid)
got = fire(transcript("shrink", 400_000, 150_000), sid)
check("post-compaction drop returns to silent", got == "SILENT", got)
clean(sid)

print("\n=== 4. once per band, but bands still escalate ===")
sid = "TEST-gate"
clean(sid)
p1, p3 = transcript("g1", 210_000), transcript("g3", 350_000)
r = [fire(p1, sid) for _ in range(3)]
check("band 1 fires once", "1.4x slower" in r[0] and r[1] == "SILENT" and r[2] == "SILENT", r)
check("band 3 still escalates", "Over half of all input spend" in fire(p3, sid), "")
check("no downgrade re-fire", fire(p1, sid) == "SILENT", "")
clean(sid)

print("\n=== 5. never blocks, never emits junk ===")
empty = os.path.join(TMP, "empty.jsonl")
open(empty, "w").write('{"type":"user","message":{"role":"user"}}\n')
for name, payload, raw in [
    ("missing transcript_path", {"session_id": "x", "prompt": "y"}, None),
    ("nonexistent file", {"transcript_path": "/nope/none.jsonl", "session_id": "x"}, None),
    ("empty json object", {}, None),
    ("transcript with no usage", {"transcript_path": empty, "session_id": "TEST-nu"}, None),
    ("malformed stdin", None, "this is not json"),
    ("empty stdin", None, ""),
]:
    out, err, rc = run(payload, raw)
    check(name, rc == 0 and out == "", f"rc={rc} out={out[:60]} err={err[:60]}")

print("\n=== 6. output shape is a non-blocking UserPromptSubmit context injection ===")
sid = "TEST-shape"
clean(sid)
out, _, _ = run({"transcript_path": transcript("shape", 320_000), "session_id": sid, "prompt": "x"})
try:
    j = json.loads(out)
    check("valid JSON", True)
    check("hookEventName is UserPromptSubmit", j["hookSpecificOutput"]["hookEventName"] == "UserPromptSubmit")
    check("carries no decision/block key", "decision" not in j, list(j.keys()))
    txt = j["hookSpecificOutput"]["additionalContext"]
    check("states the measured depth", "k tokens" in txt, txt[:90])
except Exception as e:
    check("valid JSON", False, e)
clean(sid)

print("\n=== 7. the hook counts and does not prescribe ===")
# The header says: "this hook counts, states the number, and stops there."
# Bands 2 and 3 did not. They told the assistant who decides a handoff, which
# `rules/autonomy.md` already owns and answers differently inside an unattended
# run -- there the handoff is a mandated step, not the user's call. Measured
# 2026-08-17: band-3's wording came back as a near-verbatim translation in six
# real sessions, one of which declined to launch a remaining gate in order to ask.
#
# Asserting on the emitted message, not on a helper: a test that pinned band
# numbers would stay green against a re-introduced prescription. The previous
# version of this file asserted the prescription was PRESENT, which is why it
# shipped.
PRESCRIPTIONS = [
    "do not hand off on your own",
    "the decision is theirs",
    "let them decide",
    "offer to draft",
    "mention this to the user",
    "tell the user",
]
for band_name, depth in [("band 2 (250k)", 260_000), ("band 3 (300k)", 320_000)]:
    sid = f"TEST-noprescribe-{depth}"
    clean(sid)
    out, _, _ = run({"transcript_path": transcript(f"np{depth}", depth),
                     "session_id": sid, "prompt": "x"})
    try:
        txt = json.loads(out)["hookSpecificOutput"]["additionalContext"].lower()
    except Exception as e:
        check(f"{band_name} emits parseable context", False, e)
        clean(sid)
        continue
    found = [p for p in PRESCRIPTIONS if p in txt]
    check(f"{band_name} prescribes no handoff decision", not found, found)
    check(f"{band_name} still reports the number", "k tokens" in txt, txt[:70])
    clean(sid)

for f in os.listdir(TMP):
    os.remove(os.path.join(TMP, f))
os.rmdir(TMP)

print("\n" + ("ALL PASS" if not fails else f"{len(fails)} FAILURES: {fails}"))
sys.exit(1 if fails else 0)
