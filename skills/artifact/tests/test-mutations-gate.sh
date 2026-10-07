#!/usr/bin/env bash
# test-mutations-gate.sh — mutations_gate.py's own logic, with FAKE builder/verbs/save-reply/check
# scripts (AIDEX_ARTIFACT_SCRIPTS) and a FAKE probe (AIDEX_RENDER_PROBE): no real build, no browser.
# It never asserts what today's builder does (that moves as fixes land); it asserts how the GATE
# judges each kind of outcome: a refusal with a traceback is a FAIL, a clean refusal a PASS, a silent
# wrong page a FAIL, a refusal that leaves a half-written page or spec a FAIL, a valid page needs 0
# probe violations AND its meaning predicates, one probe call for all pages, the output line and exit
# codes, and the case table's coverage of the grammar-table rows.
# Layer: script-level (bash driving a Python CLI) — the decision is in the gate, not in the pixels.
# Run with: bash skills/artifact/tests/test-mutations-gate.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$HERE/mutations_gate.py"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

FS="$TMP/scripts"; mkdir -p "$FS"
# --- fake spec_build.py: FAKE_BUILD picks the behaviour, FAKE_PAGE is the page text a build writes
cat > "$FS/spec_build.py" <<'PY'
import os, sys
mode = os.environ.get("FAKE_BUILD", "accept")
spec, page = sys.argv[1], sys.argv[sys.argv.index("-o") + 1]
if mode == "traceback":
    sys.stderr.write("Traceback (most recent call last):\n  File \"x.py\", line 1, in <module>\nKeyError: 'x'\n"); sys.exit(1)
if mode == "refuse":
    sys.stderr.write("%s:6: `item` takes no attr 'name' (it takes: title)\n" % spec); sys.exit(1)
if mode == "refuse-unrelated":
    sys.stdout.write("  WARN [consult-heading-statement] m.html: 'Q2' has options but its markdown heading states instead of asking\n")
    sys.stderr.write('FAIL [unique-dom-ids] m.html: line 9: id "X" is used again (first on line 3)\n'); sys.exit(1)
if mode == "refuse-silent":
    sys.exit(1)
if mode == "refuse-vague":
    sys.stderr.write("something went wrong\n"); sys.exit(1)
if mode == "refuse-half":
    open(page, "w").write("<main>half</main>"); sys.stderr.write("%s:6: `item` takes no attr 'name'\n" % spec); sys.exit(1)
open(page, "w").write(open(os.environ["FAKE_PAGE"]).read())
PY
# --- fake spec_verbs.py: FAKE_VERB accept | refuse | refuse-half-spec
cat > "$FS/spec_verbs.py" <<'PY'
import os, sys
mode = os.environ.get("FAKE_VERB", "accept")
spec = sys.argv[2]
if mode == "refuse":
    sys.stderr.write(os.environ["FAKE_VERB_MSG"] + "\n"); sys.exit(1)
if mode == "refuse-half-spec":
    open(spec, "a").write("\n::: junk\n"); sys.stderr.write(os.environ["FAKE_VERB_MSG"] + "\n"); sys.exit(1)
print("ok")
PY
printf '#!/usr/bin/env bash\ncat >/dev/null\necho "reply saved"\n' > "$FS/save-reply.sh"
printf '#!/usr/bin/env bash\necho "contract OK"\n' > "$FS/check-artifact.sh"

printf '<main><section class="consult-item" data-id="Q1"><input data-label="Sí"><span class="hint">pista uno</span><input data-label="x - y"></section></main>' > "$TMP/page-wrong"
printf '<main><section class="consult-item" data-id="Q1"><input data-label="Sí"><span class="hint">pista uno</span></section></main>' > "$TMP/page-right"
printf '<main><header class="masthead"></header><header class="masthead"></header></main>' > "$TMP/page-two-mast"
printf '<main><header class="masthead"></header></main>' > "$TMP/page-one-mast"

pr() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$TMP/$1.sh"; }
pr probe-clean 'echo "$@" >> "$TMP_LOG"; shift; echo "INVARIANTS pages=$# violations=0"; exit 0'
pr probe-geo   'if [[ "$1" == --invariants ]]; then shift; echo "INVARIANTS pages=$# violations=0"; exit 0; fi
for p in "$@"; do echo "DEFECT $(basename "$p") @1280px text-overlap"; done; exit 1'
pr probe-geo-crash 'if [[ "$1" == --invariants ]]; then shift; echo "INVARIANTS pages=$# violations=0"; exit 0; fi; exit 4'
pr probe-batchcrash 'shift; if [[ $# -gt 1 ]]; then exit 4; fi; echo "INVARIANTS pages=$# violations=0"; exit 0'
pr probe-pagecrash 'shift; for p in "$@"; do case "$p" in *m28b*) exit 4;; esac; done; echo "INVARIANTS pages=$# violations=0"; exit 0'
pr probe-flag  'shift; for p in "$@"; do echo "INV NAV-7 $(basename "$p") id twice"; done; echo "INVARIANTS pages=$# violations=$#"; exit 1'
pr probe-crash 'echo boom >&2; exit 4'
pr probe-silent 'exit 0'
: > "$TMP/log"

# gate [env...] -- args  -> out in $TMP/out, stderr in $TMP/err, rc in $rc
gate() {
  local envs=() a
  while [[ $# -gt 0 && "$1" != "--" ]]; do envs+=("$1"); shift; done; shift
  env "${envs[@]}" AIDEX_ARTIFACT_SCRIPTS="$FS" TMP_LOG="$TMP/log" python3 "$GATE" "$@" >"$TMP/out" 2>"$TMP/err"; rc=$?
}
line() { [[ "$(<"$TMP/out")" == "$1" ]]; }

echo "== refusals =="
gate FAKE_BUILD=traceback AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 1 --verbose
{ line "mutations: 0/1" && [[ $rc -eq 1 ]] && grep -q 'FAIL 1 ' "$TMP/err" && grep -q traceback "$TMP/err"; } \
  && ok "a refusal that is a Python traceback is a FAIL (never loud)" || bad "traceback: rc=$rc $(<"$TMP/out") / $(head -3 "$TMP/err")"
gate FAKE_BUILD=refuse AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 1
{ line "mutations: 1/1" && [[ $rc -eq 0 ]]; } && ok "a clean refusal naming the problem passes (exit 0 at 1/1)" || bad "clean refusal: rc=$rc $(<"$TMP/out") $(<"$TMP/err")"
gate FAKE_BUILD=refuse-unrelated AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 48 --verbose
{ line "mutations: 0/1" && grep -q 'does not name the problem' "$TMP/err"; } \
  && ok "an unrelated refusal plus the heading WARN does not satisfy a names regex (WARN lines are ignored)" || bad "unrelated: $(<"$TMP/out") $(head -3 "$TMP/err")"
gate FAKE_BUILD=refuse-silent AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 1
{ line "mutations: 0/1" && [[ $rc -eq 1 ]]; } && ok "a non-zero exit with no message is a FAIL" || bad "silent refusal: rc=$rc $(<"$TMP/out")"
gate FAKE_BUILD=refuse-vague AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 1 --verbose
{ line "mutations: 0/1" && grep -q 'does not name the problem' "$TMP/err"; } && ok "a refusal that does not name the problem is a FAIL" || bad "vague refusal: $(<"$TMP/out") $(head -3 "$TMP/err")"
gate FAKE_BUILD=refuse-half AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 1 --verbose
{ line "mutations: 0/1" && grep -q 'half-written' "$TMP/err"; } && ok "a refusal that leaves a page behind is a FAIL (half-written)" || bad "half page: $(<"$TMP/out") $(head -3 "$TMP/err")"
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-right" AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 1 --verbose
{ line "mutations: 0/1" && grep -q 'silently accepted' "$TMP/err"; } && ok "silent acceptance where only a refusal is right is a FAIL" || bad "accept on a refuse case: $(<"$TMP/out")"

echo "== verbs =="
V="env FAKE_BUILD=accept FAKE_PAGE=$TMP/page-right AIDEX_RENDER_PROBE=$TMP/probe-clean.sh"
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-right" FAKE_VERB=refuse FAKE_VERB_MSG="spec-verbs decide: an empty verdict for #Q1" AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 53c
{ line "mutations: 1/1" && [[ $rc -eq 0 ]]; } && ok "a verb refusal that names the right thing and touches nothing passes" || bad "verb refusal: $(<"$TMP/out") $(<"$TMP/err")"
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-right" FAKE_VERB=refuse FAKE_VERB_MSG="spec-verbs decide: no block with id #Q9 in the spec" AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 53c --verbose
{ line "mutations: 0/1" && grep -q 'does not name the problem' "$TMP/err"; } && ok "a loud refusal for ANOTHER reason is a FAIL (wrong-reason refusal)" || bad "wrong reason: $(<"$TMP/out") $(head -3 "$TMP/err")"
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-right" FAKE_VERB=refuse-half-spec FAKE_VERB_MSG="spec-verbs decide: an empty verdict for #Q1" AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 53c --verbose
{ line "mutations: 0/1" && grep -q 'spec was changed' "$TMP/err"; } && ok "a verb refusal that edited the spec is a FAIL (half-written)" || bad "verb half spec: $(<"$TMP/out") $(head -3 "$TMP/err")"
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-right" FAKE_VERB=accept AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 53c
line "mutations: 0/1" && ok "a verb that accepts an empty verdict is a FAIL" || bad "verb accepts: $(<"$TMP/out")"
gate FAKE_BUILD=refuse AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 53c --verbose
{ line "mutations: 0/1" && grep -q 'HARNESS FAULT' "$TMP/err"; } && ok "a setup step that fails is reported as a harness fault, not a pass" || bad "setup fault: $(<"$TMP/out") $(head -3 "$TMP/err")"

echo "== valid pages: probe AND meaning =="
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-wrong" AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 17 --verbose
{ line "mutations: 1/2" && grep -q 'FAIL 17 ' "$TMP/err" && grep -q 'took effect silently' "$TMP/err"; } && ok "a clean-probe page whose meaning differs from the intent is a FAIL" || bad "silent wrong page: $(<"$TMP/out") $(head -3 "$TMP/err")"
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-right" AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 17b
{ line "mutations: 1/1" && [[ $rc -eq 0 ]]; } && ok "a clean-probe page that carries the intent passes" || bad "right page: $(<"$TMP/out")"
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-right" AIDEX_RENDER_PROBE="$TMP/probe-flag.sh" -- --only 17b --verbose
{ line "mutations: 0/1" && grep -q 'violates 1 invariant' "$TMP/err"; } && ok "a page with a probe violation is a FAIL even when its meaning is right" || bad "probe violation: $(<"$TMP/out")"
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-two-mast" AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 28
line "mutations: 0/2" && ok "a count predicate (one masthead) fails a page with two" || bad "count fail: $(<"$TMP/out")"
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-one-mast" AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 28
line "mutations: 2/2" && ok "a count predicate passes a page with exactly one" || bad "count pass: $(<"$TMP/out")"

echo "== geometry =="
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-right" AIDEX_RENDER_PROBE="$TMP/probe-geo.sh" -- --only 45b --verbose
{ line "mutations: 0/1" && grep -q 'geometry defects' "$TMP/err"; } && ok "a page clean on invariants but with a geometry DEFECT is a FAIL (long-token cases)" || bad "geometry: $(<"$TMP/out") $(head -3 "$TMP/err")"
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-right" AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 45b
line "mutations: 1/1" && ok "a clean geometry run passes the long-token case" || bad "geometry clean: $(<"$TMP/out")"
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-right" AIDEX_RENDER_PROBE="$TMP/probe-geo-crash.sh" -- --only 45b --verbose
{ line "mutations: 0/1" && grep -q 'geometry probe gave no verdict' "$TMP/err"; } && ok "a geometry probe that crashes is a FAIL, never a pass" || bad "geometry crash: $(<"$TMP/out")"

echo "== probe fallback: one page that crashes the batch =="
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-one-mast" AIDEX_RENDER_PROBE="$TMP/probe-batchcrash.sh" -- --only 28
line "mutations: 2/2" && ok "a batch the probe cannot take is re-probed page by page and still judged" || bad "batch fallback: $(<"$TMP/out")"
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-one-mast" AIDEX_RENDER_PROBE="$TMP/probe-pagecrash.sh" -- --only 28 --verbose
{ line "mutations: 1/2" && grep -q 'probe crashed on this page' "$TMP/err"; } && ok "the page that crashes the probe fails alone; the rest keep their verdict (not 0/unknown)" || bad "page crash: $(<"$TMP/out") $(head -3 "$TMP/err")"

echo "== one probe call, probe verdicts, output shape =="
: > "$TMP/log"
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-one-mast" AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 28
{ [[ "$(grep -c -- '--invariants' "$TMP/log")" == 1 ]] && [[ "$(grep -o 'm28' "$TMP/log" | wc -l | tr -d ' ')" -ge 2 ]]; } \
  && ok "two pages are probed in ONE --invariants call" || bad "probe calls: $(cat "$TMP/log")"
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-right" AIDEX_RENDER_PROBE="$TMP/probe-crash.sh" -- --only 17b
{ line "mutations: 0/unknown" && [[ $rc -eq 1 ]]; } && ok "a crashed probe prints mutations: 0/unknown and exits 1" || bad "probe crash: rc=$rc $(<"$TMP/out")"
gate FAKE_BUILD=accept FAKE_PAGE="$TMP/page-right" AIDEX_RENDER_PROBE="$TMP/probe-silent.sh" -- --only 17b
{ line "mutations: 0/unknown" && [[ $rc -eq 1 ]]; } && ok "a probe with no summary line reads 0/unknown" || bad "probe silent: rc=$rc $(<"$TMP/out")"
gate FAKE_BUILD=refuse AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 99
{ line "mutations: 0/0" && [[ $rc -eq 1 ]]; } && ok "no case selected is mutations: 0/0 and never green (Y >= 1)" || bad "empty selection: rc=$rc $(<"$TMP/out")"
gate FAKE_BUILD=refuse AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 1
{ [[ "$(wc -l < "$TMP/out" | tr -d ' ')" == 1 ]] && grep -Eq '^mutations: [0-9]+/([0-9]+|unknown)$' "$TMP/out"; } \
  && ok "exactly one stdout line of the shape mutations: X/Y" || bad "shape: $(<"$TMP/out")"
gate FAKE_BUILD=traceback AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 1 --verbose
{ grep -q 'reproduce: python3 .*--only 1 --verbose' "$TMP/err" && grep -q 'commands' "$TMP/err"; } \
  && ok "--verbose names the row, the reproduce command and the commands run" || bad "verbose: $(head -5 "$TMP/err")"
gate FAKE_BUILD=refuse AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" -- --only 1
[[ -z "$(<"$TMP/err")" ]] && ok "no stderr noise without --verbose" || bad "stderr: $(<"$TMP/err")"

echo "== the case table =="
python3 - "$HERE" >"$TMP/out" 2>"$TMP/err" <<'PY'
import re, sys
sys.path.insert(0, sys.argv[1])
import mutations_gate as g
ids = [c["id"] for c in g.CASES]
assert len(ids) == len(set(ids)), "duplicate case ids"
rows = {int(m.group(1)) for i in ids for m in [re.match(r"(\d+)", i)] if m}
missing = sorted(set(range(1, 76)) - rows - set(g.SKIPPED))
assert not missing, "grammar-table section 5 rows with no case and no SKIPPED reason: %s" % missing
assert len(ids) == g.EXPECTED_CASES, "EXPECTED_CASES %d, table has %d" % (g.EXPECTED_CASES, len(ids))
# no refusal regex may be satisfied by an UNRELATED stock refusal (the heading WARN is filtered out first)
STOCK = ['FAIL [unique-dom-ids] m.html: line 9: id "X" is used again (first on line 3): getElementById resolves to the first',
         "spec-build: no document title — give the masthead a title, or pass --title",
         "ERROR: round 1 is already open and has no saved reply. If this is a re-wrap, drop --new-round, or run save-reply.sh",
         "m.spec.md:3: `item` takes no attr 'foo' (it takes: decided, dropped, free, heading, proposal, select, title)",
         'FAIL [lang-follows-profile] m.html: line 2: <html lang="es"> but the artifact profile of /x/.context declares language: en',
         "ERROR: this wrap FAILS the artifact contract above, so nothing was written at /x/m.html: do not open or hand over the failing render."]
OWN = {"29": 1, "30": 1, "30b": 1, "30c": 1, "58": 2, "58b": 2}     # a case may match the stock line it is about
for c in g.CASES:
    if c["names"]:
        for i, s in enumerate(STOCK):
            if OWN.get(c["id"]) == i:
                continue
            assert not re.search(c["names"], s, re.I), "case %s: /%s/ is satisfied by an unrelated refusal: %s" % (c["id"], c["names"], s)
for c in g.CASES:
    assert c["expect"] in ("refuse", "valid", "either"), c["id"]
    if c["expect"] in ("refuse", "either"):
        assert c["names"], "case %s: a refusal must say what it has to name" % c["id"]
        re.compile(c["names"])
    assert c["steps"], c["id"]
assert len(ids) >= 75, len(ids)
print(len(ids))
PY
rc=$?
[[ $rc -eq 0 ]] && ok "every grammar-table row 1..75 has a case or a documented skip; ids unique; refusals name something ($(<"$TMP/out") cases)" || bad "table: $(<"$TMP/err")"

echo "$PASS ok, $FAIL failed"
[[ $FAIL -eq 0 ]]
