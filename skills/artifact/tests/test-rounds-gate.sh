#!/usr/bin/env bash
# test-rounds-gate.sh — rounds_gate.py's own logic. Layer: CLI integration (the gate is a script
# whose contract is its stdout line, exit code and the checks it makes), with fake scripts
# (AIDEX_ROUNDS_SCRIPTS) and a fake probe (AIDEX_RENDER_PROBE) wherever the real tools or the
# browser are not the point. Checked: determinism per seed, the one-line shape, exit codes
# (green only at X == Y and Y >= 50), each model check firing on a crafted bad page (lost
# answer, never-answered item decided, renumbered id, wrong round, ledger row changed,
# stale proposal), any refusal of a legitimate step failing, the depth floor, probe
# verdicts attributed to their sequence and a probe without a verdict failing every sequence.
# Run with: bash skills/artifact/tests/test-rounds-gate.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$HERE/rounds_gate.py"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

fakeprobe() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$TMP/$1.sh"; }
fakeprobe clean 'shift; echo "INVARIANTS pages=$# violations=0"; exit 0'
fakeprobe flag 'shift; for p in "$@"; do echo "INV NAV-1 $(basename "$p") ids=$(grep -c "data-id=" "$p")"; done
echo "INVARIANTS pages=$# violations=$#"; [ $# -eq 0 ]'
fakeprobe crash 'echo boom >&2; exit 4'
SEED=4          # a short sequence (3 rounds of tools, a few seconds)

gate() {   # gate PROBE ARGS... -> $TMP/out $TMP/err, exit code in $rc
  local probe="$1"; shift
  AIDEX_RENDER_PROBE="$TMP/$probe.sh" python3 "$GATE" "$@" >"$TMP/out" 2>"$TMP/err"; rc=$?
}

echo "== line shape and exit code =="
gate clean --seed $SEED --count 1
[[ "$(wc -l <"$TMP/out" | tr -d ' ')" == 1 && "$(<"$TMP/out")" == "rounds: 1/1" ]] \
  && ok "stdout is exactly one line, 'rounds: 1/1', on a clean sequence" || bad "stdout: $(<"$TMP/out")"
[[ $rc -eq 1 ]] && ok "exit 1 although every sequence passed: fewer than 50 sequences is never green" || bad "exit $rc at 1/1"
grep -q "base seed $SEED" "$TMP/err" && ok "the base seed is printed on stderr" || bad "stderr: $(<"$TMP/err")"
! grep -q Traceback "$TMP/err" && ok "no traceback from the gate itself" || bad "traceback: $(<"$TMP/err")"

echo "== exit codes (green only at X == Y and Y >= 50) =="
python3 - "$HERE" <<'PY' && ok "verdict(): 50/50 and 51/51 exit 0; 49/49, 50/49, 0/0 exit 1" || bad "verdict table"
import sys
sys.path.insert(0, sys.argv[1])
import rounds_gate as g
assert [g.verdict(*t) for t in [(50, 50), (51, 51), (49, 49), (50, 49), (0, 0)]] == [0, 0, 1, 1, 1]
PY
python3 - "$HERE" >"$TMP/out" 2>/dev/null <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import rounds_gate as g
def ok_seq(s):
    q = g.Sequence(s, "", "")
    q.saves = 1                  # passed: no failure and one save-reply succeeded
    return q
g.run_batch = lambda seeds: [ok_seq(s) for s in seeds]
sys.exit(g.main(["--count", "50"]))
PY
rc=$?
[[ $rc -eq 0 && "$(<"$TMP/out")" == "rounds: 50/50" ]] && ok "main(): 50 passing sequences print 'rounds: 50/50' and exit 0" || bad "main green: rc=$rc $(<"$TMP/out")"

python3 - "$HERE" >"$TMP/out" 2>/dev/null <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import rounds_gate as g
g.run_batch = lambda seeds: [g.Sequence(s, "", "") for s in seeds]      # no step ran, no save
sys.exit(g.main(["--count", "50"]))
PY
rc=$?
[[ $rc -eq 1 && "$(<"$TMP/out")" == "rounds: 0/50" ]] && ok "main(): 50 sequences with no step and no save read 0/50 (depth floor), exit 1" || bad "zero-step fixture: rc=$rc $(<"$TMP/out")"

echo "== determinism per seed =="
gate flag --seed $SEED --count 1 --verbose; a="$(cat "$TMP/out" "$TMP/err")"
gate flag --seed $SEED --count 1 --verbose; b="$(cat "$TMP/out" "$TMP/err")"
[[ "$a" == "$b" && "$a" == *"check=invariant:NAV-1"* ]] && ok "the same seed reports the same failure twice, byte for byte" || bad "run 1: $a // run 2: $b"
gate flag --seed 5 --count 1 --verbose; c="$(cat "$TMP/out" "$TMP/err")"
[[ "$c" != "$a" ]] && ok "another seed is another sequence" || bad "seeds 4 and 5 gave one report"
[[ "$a" == *"replay: python3 "*"rounds_gate.py --seed $SEED --count 1 --verbose"* && "$a" == *"expected:"* && "$a" == *"got:"* ]] \
  && ok "--verbose names seed, step, expected, got and a replay command" || bad "verbose: $a"

echo "== probe verdicts =="
gate flag --seed $SEED --count 1
[[ "$(<"$TMP/out")" == "rounds: 0/1" ]] && ok "an invariant violation on a built page fails its sequence" || bad "flag: $(<"$TMP/out")"
gate crash --seed $SEED --count 1 --verbose
[[ "$(<"$TMP/out")" == "rounds: 0/1" ]] && grep -q "check=probe-no-verdict" "$TMP/err" \
  && ok "a probe with no verdict fails (never reads as clean)" || bad "crash: $(<"$TMP/out") $(<"$TMP/err")"

fakeprobe lines-short 'shift; echo "INV NAV-1 $(basename "$1") x"; echo "INVARIANTS pages=$# violations=2"; exit 1'
fakeprobe rc-clean 'shift; echo "INV NAV-1 $(basename "$1") x"; echo "INVARIANTS pages=$# violations=1"; exit 0'
fakeprobe rc-dirty 'shift; echo "INVARIANTS pages=$# violations=0"; exit 1'
for pr in lines-short rc-clean rc-dirty; do
  gate $pr --seed $SEED --count 1 --verbose
  [[ "$(<"$TMP/out")" == "rounds: 0/1" ]] && grep -q "check=probe-no-verdict" "$TMP/err" \
    && ok "an inconsistent probe verdict ($pr) is no verdict" || bad "$pr: $(<"$TMP/out") $(<"$TMP/err")"
done

echo "== a traceback, a crash and any refusal fail =="
mkdir -p "$TMP/fake"
printf 'import sys\nraise KeyError("boom")\n' > "$TMP/fake/spec_build.py"
AIDEX_ROUNDS_SCRIPTS="$TMP/fake" gate clean --seed $SEED --count 1 --verbose
[[ "$(<"$TMP/out")" == "rounds: 0/1" ]] && grep -q "check=traceback" "$TMP/err" \
  && ok "a step that dies with a Python traceback fails the sequence" || bad "traceback: $(<"$TMP/out") $(<"$TMP/err")"
printf 'import sys\nsys.stderr.write("spec-build: line 3: nothing to build\\n")\nsys.exit(1)\n' > "$TMP/fake/spec_build.py"
AIDEX_ROUNDS_SCRIPTS="$TMP/fake" gate clean --seed $SEED --count 1 --verbose
[[ "$(<"$TMP/out")" == "rounds: 0/1" ]] && grep -q "check=step-refused" "$TMP/err" \
  && ok "a named refusal of a legitimate step (rc 1, a message) fails: check=step-refused" || bad "refusal: $(<"$TMP/out") $(<"$TMP/err")"
printf 'import sys\nsys.exit(1)\n' > "$TMP/fake/spec_build.py"
AIDEX_ROUNDS_SCRIPTS="$TMP/fake" gate clean --seed $SEED --count 1 --verbose
[[ "$(<"$TMP/out")" == "rounds: 0/1" ]] && grep -q "check=step-refused" "$TMP/err" \
  && ok "a silent refusal fails too" || bad "silent: $(<"$TMP/out") $(<"$TMP/err")"
AIDEX_ROUNDS_SCRIPTS="$TMP/fake" gate clean --count 50
[[ "$(<"$TMP/out")" == "rounds: 0/50" && $rc -eq 1 ]] \
  && ok "a build that refuses everything, at 50 sequences, reads 0/50 and exits 1 (never 50/50)" || bad "refuse-all: rc=$rc $(<"$TMP/out")"
printf 'import sys\nsys.stderr.write("Fatal Python error: boom\\n")\nsys.exit(1)\n' > "$TMP/fake/spec_build.py"
AIDEX_ROUNDS_SCRIPTS="$TMP/fake" gate clean --seed $SEED --count 1 --verbose
grep -q "check=crash" "$TMP/err" && ok "a Fatal Python error is a crash" || bad "fatal: $(<"$TMP/err")"

echo "== the model checks fire on a crafted bad page =="
python3 - "$HERE" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import rounds_gate as g

def item(i, verdict=None, proposal=False):
    it = g.Item(i, "T " + i, "G1", ["A", "B"], 0, decided=verdict, proposal=proposal)
    return it

def model(items, rnd=2, **kw):
    m = {"items": items, "round": rnd, "ledger_expect": None, "ledger_seen": {}, "stamps": {}}
    m.update(kw)
    return m

def page(items, rnd=2, ledger=None):
    return {"round": rnd, "items": items, "ledger": ledger or {}}

def names(found):
    return sorted({f[0] for f in found})

good = page([("Q1", "A", False, 2), ("Q2", None, False, None), ("Q3", None, False, None)])
m = model([item("Q1", "A"), item("Q2"), item("Q3")], stamps={"Q1": 2})
cases = [
    ("a clean page raises nothing", m, good, {"Q1"}, []),
    ("a lost answer", m, page([("Q1", "A", False, 2), ("Q3", None, False, None)]), {"Q1", "Q2"}, ["answered-id-lost"]),
    ("a never-answered item decided", m,
     page([("Q1", "A", False, 2), ("Q2", "B", False, 2), ("Q3", None, False, None)]), {"Q1"}, ["never-answered-decided"]),
    ("a renumbered id", m, page([("Q1", "A", False, 2), ("Q2", None, False, None), ("Q9", None, False, None)]),
     {"Q1"}, ["id-renumbered"]),
    ("a lost decision", m, page([("Q1", None, False, None), ("Q2", None, False, None), ("Q3", None, False, None)]),
     {"Q1"}, ["decision-lost"]),
    ("a wrong round", m, page(good["items"], rnd=3), {"Q1"}, ["round-number"]),
    ("a reordered page", m, page([("Q3", None, False, None), ("Q2", None, False, None), ("Q1", "A", False, 2)]),
     {"Q1"}, ["id-reordered"]),
    ("a proposal that did not expire", model([item("Q1", "A"), item("Q2"), item("Q3")], stamps={"Q1": 2}),
     page([("Q1", "A", True, 2), ("Q2", None, False, None), ("Q3", None, False, None)]), {"Q1"}, ["proposal-state"]),
    ("a decided-round stamp that moved", m,
     page([("Q1", "A", False, 1), ("Q2", None, False, None), ("Q3", None, False, None)]), {"Q1"}, ["decided-round-stamp"]),
    ("a rail that reads another round than the meta", m,
     dict(good, shown=1), {"Q1"}, ["rail-round"]),
    ("a ledger row missing after a sync", model(m["items"], ledger_expect={"Q1": 1}, stamps={"Q1": 2}), good, {"Q1"}, ["ledger-rows"]),
    ("a ledger row whose text changed", model(m["items"], ledger_seen={"Q1": "T Q1 (A)"}, stamps={"Q1": 2}),
     page(good["items"], ledger={"Q1": "T Q1 (B)"}), {"Q1"}, ["ledger-row-changed"]),
]
bad = 0
for what, mod, pg, ans, want in cases:
    got = names(g.check_model(mod, pg, ans))
    if got != want:
        bad += 1
        print("  FAIL: %s: expected %s, got %s" % (what, want, got), file=sys.stderr)
    else:
        print("  ok: %s -> %s" % (what, want or "no violation"))
sys.exit(bad)
PY
rc=$?
[[ $rc -eq 0 ]] && ok "all model checks agree with their crafted pages ($rc failures)" || bad "$rc model check(s) wrong"

echo "== sequence-level checks (a saved reply, a dropped id) =="
python3 - "$HERE" "$TMP" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import rounds_gate as g

def seq(name, reply_md, items, answered):
    d = os.path.join(sys.argv[2], name)
    os.makedirs(os.path.join(d, ".aidex-artifact-prev"))
    with open(os.path.join(d, ".aidex-artifact-prev", "r.reply.md"), "w") as fh:
        fh.write(reply_md)
    open(os.path.join(d, ".aidex-artifact-prev", "r.answered.html"), "w").close()
    q = g.Sequence(1, d, d)
    q.steps, q.items, q.answered = ["save-reply"], items, set(answered)
    return q

def it(i, verdict=None):
    return g.Item(i, "T " + i, "G1", ["A", "B"], 0, decided=verdict)

new = [(it("Q2"), "pick", "A")]
bad = 0
def expect(what, got, want):
    global bad
    if got != want:
        bad += 1
        print("  FAIL: %s: expected %s, got %s" % (what, want, got), file=sys.stderr)
    else:
        print("  ok: %s -> %s" % (what, want or "no violation"))

def rebuilt(name, dropped):
    q = seq(name, "", [it("Q1")] + ([] if dropped else [it("Q2")]), ["Q1", "Q2"])
    q.steps = ["new-round verb"]
    with open(q.page, "w") as fh:
        fh.write('<meta name="consult-round" content="1">\n<p class="railbuilt">Built 2026 \u00b7 round 1</p>\n<section class="consult-item" data-id="Q1" data-title="T">\n')
    q.after_rebuild()
    return [f["check"] for f in q.failures]
expect("an answered id that vanished without --drop", rebuilt("d", False), ["answered-id-lost"])
q = seq("f", "### Q2 \u00b7 T Q2\n", [it("Q1"), it("Q2")], [])
q.after_save("### Q2 \u00b7 T Q2\n", new)            # the save is what makes Q2 an answered id
q.steps = ["decide Q1"]
with open(q.page, "w") as fh:
    fh.write('<meta name="consult-round" content="2">\n<p class="railbuilt">Built 2026 \u00b7 round 2</p>\n<section class="consult-item" data-id="Q1" data-title="T">\n')
q.after_rebuild()
expect("a reply just saved makes its ids answered for the next rebuild's check",
       [f["check"] for f in q.failures], ["answered-id-lost"])
q = seq("g", "", [it("Q1"), it("Q2")], [])        # the saved reply file does not name Q2
q.after_save("### Q2 \\u00b7 T Q2\\n", new)
expect("a save whose file lacks the pasted id fails and stops the sequence",
       ([f["check"] for f in q.failures], q.alive), (["save-files"], False))
expect("a dropped id the model removed too", rebuilt("e", True), [])
sys.exit(bad)
PY
rc=$?
[[ $rc -eq 0 ]] && ok "sequence-level checks agree ($rc failures)" || bad "$rc sequence-level check(s) wrong"

echo "$PASS ok, $FAIL failed"
[[ $FAIL -eq 0 ]]
