#!/usr/bin/env bash
# test-generated-gate.sh — the logic of generated_gate.py and spec_gen.py, with a FAKE probe
# (AIDEX_RENDER_PROBE, no browser) and fake builders (the module's SPEC_BUILD seam), never the
# real defect count: determinism across processes, coverage of every builder block kind, the
# shrinker on a fake predicate, the pass/fail rule (a traceback refusal fails, a clean refusal
# passes, a half-written refusal fails, a probe with no verdict fails), the one-probe-call rule,
# the one-line stdout, and the exit rule (0 iff X == Y and Y >= 300).
# Layer: script-level (stdlib Python driven from bash), because the contract is the CLI's.
# Run with: bash skills/artifact/tests/test-generated-gate.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$HERE/generated_gate.py"
GEN="$HERE/spec_gen.py"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# the python cells print `ok: ...` / `FAIL: ...` lines; count them here
cells() { local out; out="$("$@" 2>&1)"; while IFS= read -r l; do
  case "$l" in "ok: "*) ok "${l#ok: }";; *) bad "$l";; esac; done <<<"$out"; }

echo "== determinism (two separate processes: hash randomisation cannot hide) =="
python3 "$GEN" 20261010 > "$TMP/a.md"; PYTHONHASHSEED=1 python3 "$GEN" 20261010 > "$TMP/b.md"
PYTHONHASHSEED=2 python3 "$GEN" 20261010 > "$TMP/c.md"; python3 "$GEN" 20261011 > "$TMP/d.md"
{ cmp -s "$TMP/a.md" "$TMP/b.md" && cmp -s "$TMP/a.md" "$TMP/c.md" && [[ -s "$TMP/a.md" ]]; } \
  && ok "the same seed gives byte-identical specs in separate processes" || bad "seed 20261010 differs between processes"
cmp -s "$TMP/a.md" "$TMP/d.md" && bad "seeds 20261010 and 20261011 gave the same spec" || ok "a different seed gives a different spec"

echo "== coverage, the shrinker, the pass rule, the exit rule (python cells) =="
cells python3 - "$HERE" "$TMP" <<'PY'
import os, re, sys, stat, subprocess, io, contextlib
here, tmp = sys.argv[1], sys.argv[2]
sys.path.insert(0, here)
import spec_gen, generated_gate as gg

def check(cond, name, why=""):
    print(("ok: " if cond else "FAIL: ") + name + ("" if cond else " -- " + why))

# --- coverage: against the builder's own emitter registry, not a hand list -----------------
src = open(os.path.join(os.path.dirname(here), "scripts", "spec_build.py"), encoding="utf-8").read()
table = set(re.findall(r'^@emitter\("([a-z-]+)"', src, re.M))
check(set(spec_gen.KINDS) == table, "KINDS equals the builder's emitter registry",
      "only in KINDS: %s, only in builder: %s" % (sorted(set(spec_gen.KINDS) - table), sorted(table - set(spec_gen.KINDS))))
check(set(spec_gen.REFUSAL_ONLY) <= table, "every REFUSAL_ONLY kind exists in the builder (no stale exclusion)")
seen, specs = set(), [spec_gen.generate(gg.BASE_SEED + i) for i in range(gg.MIN_COUNT)]
for t in specs:
    seen.update(re.findall(r"^:::+ ([a-z][a-z0-9-]*)", t, re.M))
    if re.search(r"^(?!:::)\S", t.lstrip("﻿"), re.M):   # a paragraph line outside any fence marker
        seen.add("prose")
check(table <= seen, "every builder block kind appears in the default 300 specs",
      "missing: %s" % sorted(table - seen))
langs = {re.search(r"lang=en", t) is not None for t in specs}
check(langs == {True, False}, "both page languages are generated")
check(any(len(re.findall(r"^- ", t, re.M)) >= 40 for t in specs), "an edge spec carries 40+ list lines")
check(any(spec_gen.LONG in t for t in specs), "an edge spec carries a long token")
check(any("日本語" in t or "🙂" in t for t in specs), "an edge spec carries unicode")
check(any(t.count("\r\n") for t in specs), "an edge spec has CRLF line endings")
check(sum(1 for t in specs if "visual=" in t) > 20 and sum(1 for t in specs if "visual=" not in t) > 20,
      "both consultation and presentation pages are generated")
check(specs[0] != specs[1] and len(set(specs)) == len(specs), "300 distinct specs")

# --- the shrinker, on a fake predicate ----------------------------------------------------------
big = spec_gen.generate(gg.BASE_SEED + 3) + "\n::: note\nNEEDLE-A line\n:::\n\n::: callout\nNEEDLE-B line\n:::\n"
calls = []
def pred(t):
    calls.append(t)
    return "NEEDLE-A" in t and "NEEDLE-B" in t
out = spec_gen.shrink(big, pred)
check(pred(out) and len(out) < len(big) // 3, "shrink keeps what the predicate needs and drops the rest",
      "%d -> %d bytes" % (len(big), len(out)))
check(out.count("\n") <= 8, "shrink reaches a handful of lines", "%d lines" % out.count("\n"))
check(spec_gen.shrink("a\nb\n", lambda t: t == "a\nb\n") == "a\nb\n", "a spec whose every reduction passes is returned as it is")
g = spec_gen.shrinker(big, 5); chunk = next(g); n = len(chunk)
check(1 < n <= 5, "shrinker yields a batch of up to B candidates", str(n))
try:
    nxt = g.send([False] * n)
    check(nxt != chunk, "a batch with no hit moves on to the next window")
except StopIteration:
    check(False, "shrinker ended after one all-false batch")

# --- classify_build: the pure pass/fail rule -----------------------------------------------------
cb = gg.classify_build
TB = "Traceback (most recent call last):\n  File x\nOverflowError: boom"
check(cb(1, TB, False, False) == "traceback", "a refusal with a traceback is a failure")
check(cb(0, TB, True, False) == "traceback", "a traceback fails even with exit 0")
check(cb(1, "spec.md:4: close fence with no block open", False, False) == "refused", "a named refusal passes")
check(cb(1, "spec.md:4: x", True, False) == "half-written", "a refusal that left a page is half-written")
check(cb(1, "spec.md:4: x", False, True) == "half-written", "a refusal that left residue is half-written")
check(cb(1, "  \n", False, False) == "silent-refusal", "a refusal with no message fails")
check(cb(0, "Built", True, False) == "built" and cb(0, "Built", False, False) == "no-page", "exit 0 needs a page")
check(gg.exception_name(TB) == "OverflowError" and gg.exception_name("plain") == "", "exception_name")

# --- the driver with fake builders and fake probes -----------------------------------------------
def script(name, body):
    p = os.path.join(tmp, name)
    open(p, "w").write(body)
    return p
fake_ref = script("b_ref.py", 'import sys\nsys.stderr.write("%s:3: unknown block type\\n" % sys.argv[1])\nsys.exit(1)\n')
fake_tb = script("b_tb.py", 'import sys\nsys.stderr.write("Traceback (most recent call last):\\n  File \\"x\\"\\nOverflowError: boom\\n")\nsys.exit(1)\n')
fake_half = script("b_half.py", 'import sys\nopen(sys.argv[sys.argv.index("-o")+1], "w").write("<html>")\nsys.stderr.write("refused late\\n")\nsys.exit(1)\n')
fake_ok = script("b_ok.py", 'import sys\nopen(sys.argv[sys.argv.index("-o")+1], "w").write("<html>")\nprint("Built")\n')
def kinds(builder, intent="edge", n=2):
    gg.SPEC_BUILD = builder
    shown, info = gg.exhibits([("t%d" % i, "x\n", intent) for i in range(n)])
    return shown
check(kinds(fake_ref, "edge") == [set(), set()], "a clean refusal of an EDGE spec passes (no key)")
check(kinds(fake_ref, "valid") == [{("BUILD", "valid-refused", "")}] * 2, "a refusal of an intended-VALID spec is a failure")
check(kinds(fake_ref, "refusal-only") == [{("BUILD", "wrong-refusal", "")}] * 2,
      "a refusal-only spec refused with some other message fails")
fake_gal = script("b_gal.py", 'import sys\nsys.stderr.write("%s:3: `gallery` rows=\'x\' was refused: nope\\n" % sys.argv[1])\nsys.exit(1)\n')
check(kinds(fake_gal, "refusal-only") == [set(), set()], "a refusal-only spec refused with its own message passes")
fake_crash = script("b_crash.py", 'import os, signal\nos.kill(os.getpid(), signal.SIGSEGV)\n')
check(all(next(iter(k))[1] == "crashed" for k in kinds(fake_crash)), "a builder killed by a signal fails as crashed")
fake_fatal = script("b_fatal.py", 'import sys\nsys.stderr.write("Fatal Python error: boom\\n")\nsys.exit(1)\n')
check(all(next(iter(k))[1] == "crashed" for k in kinds(fake_fatal)), "a Fatal Python error fails as crashed")
check(cb(-11, "", False, False) == "crashed", "classify_build: a negative exit code is a crash")
fake_failline = script("b_fl.py", 'import sys\nsys.stderr.write("noise first\\n  FAIL [consult-shape] x: why\\nlast\\n")\nsys.exit(1)\n')
gg.SPEC_BUILD = fake_failline
_, info = gg.exhibits([("t0", "x\n", "valid")])
check(info.get("t0", "").startswith("FAIL [consult-shape]"), "the detail is the first FAIL [ line", info.get("t0", ""))
gg.SPEC_BUILD = fake_gal
_, info = gg.exhibits([("t0", "x\n", "valid")])
check("was refused" in info.get("t0", ""), "with no FAIL [ line the detail is the first line", info.get("t0", ""))
check(all(k and next(iter(k))[:2] == ("BUILD", "traceback") for k in kinds(fake_tb)), "a traceback refusal fails with its exception")
check(next(iter(kinds(fake_tb)[0]))[2] == "OverflowError", "the failure key names the exception")
check(all(next(iter(k))[1] == "half-written" for k in kinds(fake_half)), "a refusal that wrote a page fails")

calllog = os.path.join(tmp, "probe-calls")
def probe(name, body):
    p = script(name, '#!/usr/bin/env bash\necho "$#" >> "%s"\nshift\n%s\n' % (calllog, body))
    os.chmod(p, 0o755)
    gg.PROBE = p
probe("p_clean.sh", 'echo "INVARIANTS pages=$# violations=0"')
gg.SPEC_BUILD = fake_ok
shown, _ = gg.exhibits([("t%d" % i, "x\n") for i in range(5)])
check(shown == [set()] * 5, "built pages with a clean probe pass")
calls_n = open(calllog).read().split()
check(calls_n == ["6"], "all built pages go through ONE probe call", "calls (argc incl. flag): %s" % calls_n)
probe("p_flag.sh", 'for p in "$@"; do case "$p" in *t1.html) echo "INV NAV-4 $(basename "$p") label x";; esac; done\necho "INVARIANTS pages=$# violations=1"; exit 1')
shown, info = gg.exhibits([("t%d" % i, "x\n") for i in range(3)])
check(shown[1] == {("INV", "NAV-4")} and shown[0] == set() and shown[2] == set(), "a violation fails only its own page")
check(info.get("t1 NAV-4") == "label x", "the violation message is kept")
probe("p_silent.sh", 'exit 0')
with contextlib.redirect_stderr(io.StringIO()):
    shown, _ = gg.exhibits([("t0", "x\n")])
check(shown == [{("BUILD", "no-verdict", "")}], "a probe with no verdict fails the page it should have judged")
probe("p_short.sh", 'echo "INVARIANTS pages=0 violations=0"')
with contextlib.redirect_stderr(io.StringIO()):
    shown, _ = gg.exhibits([("t0", "x\n"), ("t1", "x\n")])
check(all(k == {("BUILD", "no-verdict", "")} for k in shown), "a probe that judged fewer pages than given fails them")
probe("p_crash.sh", 'echo boom >&2; exit 4')
with contextlib.redirect_stderr(io.StringIO()):
    shown, _ = gg.exhibits([("t0", "x\n")])
check(shown == [{("BUILD", "no-verdict", "")}], "a crashed probe (rc 4) fails the page")

# --- targets and the exit rule -------------------------------------------------------------------
t = gg.pick_targets({1: [("INV", "NAV-4")], 2: [("INV", "NAV-4"), ("INV", "CNT-2")], 3: [("INV", "NAV-4")]})
check(t[2] == ("INV", "CNT-2") and t[1] == ("INV", "NAV-4"), "a seed is shrunk toward the rarest key it shows")

def run_main(argv, fail_seeds=()):
    real = gg.exhibits
    def fake(items, with_probe=True):
        return [({("INV", "NAV-4")} if int(it[0][1:]) in fail_seeds else set()) for it in items], {}
    gg.exhibits = fake
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(io.StringIO()):
            rc = gg.main(argv)
    finally:
        gg.exhibits = real
    return rc, buf.getvalue()
rc, out = run_main(["--count", "300"])
check((rc, out) == (0, "generated: 300/300\n"), "300/300 exits 0 with exactly one stdout line", repr((rc, out)))
rc, out = run_main(["--count", "300"], fail_seeds=(gg.BASE_SEED + 5,))
check((rc, out) == (1, "generated: 299/300\n"), "299/300 exits 1", repr((rc, out)))
rc, out = run_main(["--count", "299"])
check((rc, out) == (1, "generated: 299/299\n"), "299/299 exits 1: fewer than 300 specs never reads green", repr((rc, out)))
rc, out = run_main(["--count", "300", "--seed", "5"], fail_seeds=(5, 6))
check(out == "generated: 298/300\n", "--seed moves the whole range", repr(out))

# --- a builder that refuses everything must not read green ---------------------------------------
gg.SPEC_BUILD = fake_ref
buf, err = io.StringIO(), io.StringIO()
with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(err):
    rc = gg.main(["--count", "300"])
check(rc == 1 and buf.getvalue() != "generated: 300/300\n" and buf.getvalue().count("\n") == 1,
      "a builder that refuses every spec does not print 300/300 and exits 1", repr((rc, buf.getvalue())))
gg.SPEC_BUILD = os.path.join(os.path.dirname(here), "scripts", "spec_build.py")

# --- intents ----------------------------------------------------------------------------------
ints = [spec_gen.intent(gg.BASE_SEED + i) for i in range(gg.MIN_COUNT)]
check(set(ints) == {"valid", "edge", "refusal-only"}, "all three intents occur in the default 300", str(set(ints)))
check(ints.count("valid") > 100 and ints.count("edge") > 40, "most specs are valid, a controlled share carry an edge",
      str((ints.count("valid"), ints.count("edge"))))
check(ints.count("refusal-only") <= len(ints) // len(spec_gen.KINDS) + 2, "refusal-only stays a small fixed share (1 kind in 16)")
ro = [gg.BASE_SEED + i for i, v in enumerate(ints) if v == "refusal-only"]
check(all(spec_gen._Gen(sd).focus in spec_gen.REFUSAL_ONLY and spec_gen.generate(sd).count("::: gallery") == 1 for sd in ro),
      "refusal-only seeds are exactly the gallery-focus ones")
import spec_gen as _sg
def edge_of(sd):
    g = _sg._Gen(sd); g.spec(); return g.edge
check(all(edge_of(sd) is None for sd in ro), "no edge shape is attached to a refusal-only seed")
check(all("::: section" not in re.split(r"^::: notes", t, flags=re.M)[0].split("::: group", 1)[-1]
          for t, v in zip(specs, ints) if v == "valid" and "::: notes" in t and "::: group" in t),
      "a valid consultation page has no section between its groups and notes")

# --- build-only coverage: the REAL builder over the default 300, no probe ---------------------------
items = [("g%d" % (gg.BASE_SEED + i), specs[i], ints[i]) for i in range(gg.MIN_COUNT)]
shown, info = gg.exhibits(items, with_probe=False)
refused_valid = [it[0] for it, k in zip(items, shown) if it[2] == "valid" and k]
check(not refused_valid, "no intended-valid spec is refused or fails to build", str(refused_valid[:5]))
check(all(not k for it, k in zip(items, shown) if it[2] == "refusal-only"), "every refusal-only spec refuses with its own message")
built_seen = set()
for it, k in zip(items, shown):
    if info.get("built:" + it[0]) == "built":
        built_seen.update(re.findall(r"^:::+ ([a-z][a-z0-9-]*)", it[1], re.M))
        built_seen.add("prose")
need = table - set(spec_gen.REFUSAL_ONLY)
check(need <= built_seen, "every kind not refusal-only appears in a spec that BUILT", "missing: %s" % sorted(need - built_seen))

# --- probe parsing: an inconsistent probe is no verdict ---------------------------------------------
gg.SPEC_BUILD = fake_ok
def probed(name, body):
    probe(name, body)
    with contextlib.redirect_stderr(io.StringIO()):
        shown, _ = gg.exhibits([("t0", "x\n"), ("t1", "x\n")])
    return shown
nv = [{("BUILD", "no-verdict", "")}] * 2
check(probed("p_more.sh", 'echo "INV NAV-4 t0.html a"; echo "INVARIANTS pages=$# violations=0"; exit 1') == nv,
      "more INV lines than violations=m is no verdict")
check(probed("p_fewer.sh", 'echo "INV NAV-4 t0.html a"; echo "INVARIANTS pages=$# violations=3"; exit 1') == nv,
      "fewer INV lines than violations=m is no verdict")
check(probed("p_foreign.sh", 'echo "INV NAV-4 other.html a"; echo "INVARIANTS pages=$# violations=1"; exit 1') == nv,
      "an INV line for a page that was not given is no verdict")
check(probed("p_rc0.sh", 'echo "INV NAV-4 t0.html a"; echo "INVARIANTS pages=$# violations=1"; exit 0') == nv,
      "exit 0 with violations>0 is no verdict")
check(probed("p_rc1.sh", 'echo "INVARIANTS pages=$# violations=0"; exit 1') == nv, "exit 1 with violations=0 is no verdict")
check(probed("p_ok.sh", 'echo "INV NAV-4 t0.html a"; echo "INVARIANTS pages=$# violations=1"; exit 1')
      == [{("INV", "NAV-4")}, set()], "a consistent probe is still believed")
PY

echo "== the CLI: one stdout line, base seed on stderr, verbose and shrink-dir =="
printf '#!/usr/bin/env bash\nshift\nfor p in "$@"; do echo "INV NAV-4 $(basename "$p") fake"; break; done\necho "INVARIANTS pages=$# violations=1"; exit 1\n' > "$TMP/probe-flag-first.sh"
printf '#!/usr/bin/env bash\nshift\necho "INVARIANTS pages=$# violations=0"; exit 0\n' > "$TMP/probe-clean.sh"
AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" python3 "$GATE" --count 4 >"$TMP/out" 2>"$TMP/err"; rc=$?
[[ "$(cat "$TMP/out")" == "generated: 4/4" ]] && ok "stdout is exactly one line: generated: X/Y" || bad "stdout: $(cat "$TMP/out")"
grep -Eq "sha256 [0-9a-f]{16} " "$TMP/err" && ok "a sha256 of the generator and the gate is on stderr" || bad "no sha256: $(cat "$TMP/err")"
grep -q "base seed 20261007" "$TMP/err" && ok "the base seed is printed on stderr" || bad "stderr: $(cat "$TMP/err")"
[[ $rc -eq 1 ]] && ok "4/4 exits 1 (below the 300 floor)" || bad "exit $rc"
! grep -q Traceback "$TMP/err" && ok "no traceback from the gate itself" || bad "traceback on stderr"
AIDEX_RENDER_PROBE="$TMP/probe-flag-first.sh" python3 "$GATE" --count 6 --verbose --shrink-dir "$TMP/shr" --shrink-budget 20 >"$TMP/out" 2>"$TMP/err"; rc=$?
[[ "$(cat "$TMP/out")" =~ ^generated:\ [0-9]+/6$ && "$(wc -l <"$TMP/out")" -eq 1 && "$(cat "$TMP/out")" != "generated: 6/6" ]] \
  && ok "a flagged page shows in X/Y, still one stdout line" || bad "out: $(cat "$TMP/out")"
grep -q "FAIL seed=[0-9]* INV:NAV-4" "$TMP/err" && ok "--verbose names each failure with its seed and invariant id" || bad "verbose: $(cat "$TMP/err")"
grep -q "CLASSES" "$TMP/err" && ok "--verbose groups failures into classes" || bad "no CLASSES: $(cat "$TMP/err")"
seed="$(sed -n 's/.*FAIL seed=\([0-9]*\) .*/\1/p' "$TMP/err" | head -1)"
if [[ -n "$seed" && -f "$TMP/shr/$seed.spec.md" ]]; then
  orig="$(python3 "$GEN" "$seed" | wc -c)"; got="$(wc -c <"$TMP/shr/$seed.spec.md")"
  [[ "$got" -gt 0 && "$got" -lt "$orig" ]] && ok "--shrink-dir writes <seed>.spec.md, smaller than the generated spec ($orig -> $got bytes)" || bad "shrunk file $got vs $orig bytes"
else
  bad "no shrunk spec for seed '$seed' in $TMP/shr: $(ls "$TMP/shr" 2>&1)"
fi

echo
echo "generated-gate tests: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
