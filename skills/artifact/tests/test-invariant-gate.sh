#!/usr/bin/env bash
# test-invariant-gate.sh — invariant-gate.sh's own logic, with a FAKE probe (AIDEX_RENDER_PROBE,
# no browser) and a fake corpus built here: the seven lines and their order, `corpus: X/Y` counting
# distinct pages (a builder refusal is a failing page), a probe that gives no verdict reading
# `0/unknown`, every line needing its minimum (0/0 never green, no traceback), the stub seam
# (AIDEX_INVARIANT_STUBS) and exit 0 only when all seven are green.
# Run with: bash skills/artifact/tests/test-invariant-gate.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$HERE/invariant-gate.sh"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

fake() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$TMP/$1.sh"; }
# the arguments after --invariants are the pages
fake probe-clean 'shift; echo "INVARIANTS pages=$# violations=0"; exit 0'
# flags the page named *flag* twice (two lines, one page)
fake probe-dup 'shift; for p in "$@"; do case "$p" in *flag*) echo "INV NAV-4 $(basename "$p") a"; echo "INV CNT-2 $(basename "$p") b";; esac; done
echo "INVARIANTS pages=$# violations=2"; exit 1'
fake probe-crash 'echo "boom" >&2; exit 4'
fake probe-silent 'exit 0'

SPECS="$TMP/specs"; mkdir -p "$SPECS"
for n in clean flag; do
  printf '::: masthead {eyebrow="Test" lang=en}\n# Page %s\n\nA short report.\n:::\n\n## Findings\n\nNothing to decide here.\n' "$n" > "$SPECS/$n.spec.md"
done
printf '::: masthead {eyebrow="Test" lang=en}\n# Loose item\n\nNo block around it.\n:::\n\n::: item {#q1 title="Pick one"}\nWhich?\n\n- **A.** This\n- **B.** That\n:::\n' > "$SPECS/refused.spec.md"
CORP="$TMP/corpus"
corpus() {   # corpus SPEC... -> a corpus-sample.json + corpus-specs/cproj__SPEC.spec.md
  local rows="" s; rm -rf "$CORP"; mkdir -p "$CORP/corpus-specs"
  for s in "$@"; do
    rows+="${rows:+, }{\"path\": \"cproj/$s.html\"}"
    cp "$SPECS/$s.spec.md" "$CORP/corpus-specs/cproj__$s.spec.md"
  done
  printf '{"root": "%s", "pages": [%s]}\n' "$TMP" "$rows" > "$CORP/corpus-sample.json"
}
# the wired lines' own scripts, faked: FAKE_MUT is the line the fake mutations gate prints,
# FAKE_EXP its --expected answer
LINES="$TMP/lines"; mkdir -p "$LINES"
cat > "$LINES/mutations_gate.py" <<'PY'
import os, sys
if "--expected" in sys.argv:
    print(os.environ.get("FAKE_EXP", "1")); sys.exit(0)
line = os.environ.get("FAKE_MUT", "mutations: 0/0")
print(line) if line else None
sys.exit(0)
PY
cat > "$LINES/generated_gate.py" <<'PY'
import os
print(os.environ.get("FAKE_GEN", "generated: 0/0"))
PY
cat > "$LINES/rounds_gate.py" <<'PY'
import os
print(os.environ.get("FAKE_ROUNDS", "rounds: 0/0"))
PY
cat > "$LINES/galleries_gate.py" <<'PY'
import os, sys
if "--expected" in sys.argv:
    print(os.environ.get("FAKE_GAL_EXP", "1")); sys.exit(0)
print(os.environ.get("FAKE_GAL", "galleries: 0/0"))
PY
cat > "$LINES/hunts_gate.py" <<'PY'
import os, sys
assert sys.argv[1:] == ["--report"], sys.argv
print(os.environ.get("FAKE_HUNTS", "hunts-clean: 0"))
PY
export AIDEX_GATE_LINE_SCRIPTS="$LINES"
GREEN_STUBS='generated=300/300,rounds=50/50,mutations=1/1,galleries=1/1,hunts-clean=2'
gate() {   # gate PROBE [STUBS] -> $TMP/out; exit code in $rc; stderr in $TMP/err
  AIDEX_RENDER_PROBE="$TMP/$1.sh" AIDEX_SPEC_CORPUS="$CORP" AIDEX_INVARIANT_STUBS="${2:-}" \
    bash "$GATE" >"$TMP/out" 2>"$TMP/err"; rc=$?
}
rows="$(grep -c '^| [A-Z]*-[0-9]* |' "$HERE/invariants/catalog.md")"

echo "== the seven lines =="
corpus clean
gate probe-clean; out="$(<"$TMP/out")"
[[ "$(sed 's/:.*//' <<<"$out" | tr '\n' ' ')" == "catalog corpus generated rounds mutations galleries hunts-clean " ]] \
  && ok "seven lines in the loop spec's order" || bad "lines: $out"
[[ "$(head -1 <<<"$out")" == "catalog: $rows" ]] && ok "catalog: counts the catalog's rows ($rows)" || bad "catalog line: $(head -1 <<<"$out")"
[[ "$(sed -n 2p <<<"$out")" == "corpus: 1/1" && "$(tail -n +3 <<<"$out" | tr '\n' ' ')" == "generated: 0/0 rounds: 0/0 mutations: 0/0 galleries: 0/0 hunts-clean: 0 " ]] \
  && ok "a clean corpus reads 1/1 and the stubs read zero" || bad "corpus/stubs: $out"
[[ $rc -eq 1 ]] && ok "with the stubs at zero the gate is RED" || bad "exit $rc with zero stubs"

echo "== corpus: X/Y =="
corpus clean refused
gate probe-clean; out="$(<"$TMP/out")"
[[ "$(sed -n 2p <<<"$out")" == "corpus: 1/2" ]] && ok "a spec the builder refuses is a failing page" || bad "refused: $(sed -n 2p <<<"$out")"
# a spec the builder refuses reads its migrated copy (corpus/migrated/, same file name); the
# original stays refused in corpus-specs/, Y stays the sample size, --verbose names the copy
corpus clean refused
mkdir "$CORP/migrated"; cp "$SPECS/clean.spec.md" "$CORP/migrated/cproj__refused.spec.md"
gate probe-clean; out="$(<"$TMP/out")"
[[ "$(sed -n 2p <<<"$out")" == "corpus: 2/2 (1 migrated)" ]] && ok "a refused spec with a migrated copy is built from the copy and the line says so" || bad "migrated: $(sed -n 2p <<<"$out")"
AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" AIDEX_SPEC_CORPUS="$CORP" bash "$GATE" --verbose >/dev/null 2>"$TMP/err"
grep -q "migrated specs built.*cproj__refused.spec.md" "$TMP/err" && ok "--verbose prints the migrated spec's name" || bad "verbose: $(cat "$TMP/err")"
grep -q "cproj__clean" "$TMP/err" && bad "--verbose named an unmigrated spec" || ok "--verbose names only the migrated ones"
# a migrated copy beside an original that builds is stale: the original is used, the copy reported
corpus clean
mkdir "$CORP/migrated"; cp "$SPECS/flag.spec.md" "$CORP/migrated/cproj__clean.spec.md"
gate probe-dup; out="$(<"$TMP/out")"
[[ "$(sed -n 2p <<<"$out")" == "corpus: 1/1" ]] && grep -q "stale migration: cproj__clean.spec.md" "$TMP/err" \
  && ok "a copy beside an original that builds is ignored and reported stale" || bad "stale: $(sed -n 2p <<<"$out") / $(cat "$TMP/err")"
corpus clean flag
gate probe-dup; out="$(<"$TMP/out")"
[[ "$(sed -n 2p <<<"$out")" == "corpus: 1/2" ]] && ok "two INV lines on one page fail that one page, once" || bad "dup: $(sed -n 2p <<<"$out")"
corpus clean
gate probe-crash; out="$(<"$TMP/out")"
[[ "$(sed -n 2p <<<"$out")" == "corpus: 0/unknown" && $rc -eq 1 ]] && ok "a crashed probe (rc 4) reads 0/unknown" || bad "crash: $out"
gate probe-silent; out="$(<"$TMP/out")"
[[ "$(sed -n 2p <<<"$out")" == "corpus: 0/unknown" ]] && ok "a probe that exits 0 without its summary line reads 0/unknown" || bad "silent: $out"
out="$(AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" AIDEX_SPEC_CORPUS="$TMP/nowhere" bash "$GATE" 2>/dev/null)"
[[ "$(sed -n 2p <<<"$out")" == "corpus: 0/unknown" ]] && ok "no corpus reads 0/unknown" || bad "no corpus: $out"

echo "== every line needs its minimum =="
corpus clean
gate probe-clean 'generated=300/300,rounds=50/50,mutations=0/0,galleries=0/0,hunts-clean=2'; out="$(<"$TMP/out")"
{ [[ $rc -eq 1 ]] && ! grep -q Traceback "$TMP/err"; } && ok "mutations 0/0 and galleries 0/0 are RED, with no traceback" || bad "0/0: rc=$rc $(cat "$TMP/err")"
for s in generated=299/299 rounds=49/49 mutations=0/0 galleries=0/0 hunts-clean=1 generated=300/301; do
  gate probe-clean "$(sed "s|${s%%=*}=[^,]*|$s|" <<<"$GREEN_STUBS")"
  [[ $rc -eq 1 ]] && ok "$s is RED" || bad "$s read green"
done
corpus
gate probe-clean "$GREEN_STUBS"; out="$(<"$TMP/out")"
[[ "$(sed -n 2p <<<"$out")" == "corpus: 0/0" && $rc -eq 1 ]] && ok "an empty corpus prints corpus: 0/0 and is RED" || bad "empty corpus: rc=$rc $out"

echo "== the stub seam cannot fake a green run =="
corpus clean
gate probe-clean "$GREEN_STUBS"; out="$(<"$TMP/out")"
[[ $rc -eq 1 && "$(grep -c '(override)$' <<<"$out")" == 5 ]] \
  && ok "five overridden lines print (override) and the exit is 1 even at every minimum" || bad "override: rc=$rc $out"

echo "== a wired line comes from its own script, pinned to its --expected count =="
corpus clean
GN='galleries=1/1,hunts-clean=2'
FAKE_MUT="mutations: 7/9" FAKE_GEN="generated: 299/300" FAKE_ROUNDS="rounds: 49/50" gate probe-clean "$GN"; out="$(<"$TMP/out")"
[[ "$(sed -n 3p <<<"$out")" == "generated: 299/300" ]] && ok "generated: is its script's own line" || bad "wired gen: $out"
[[ "$(sed -n 4p <<<"$out")" == "rounds: 49/50" ]] && ok "rounds: is its script's own line" || bad "wired rounds: $out"
[[ "$(sed -n 5p <<<"$out")" == "mutations: 7/9" ]] && ok "mutations: is the script's own line" || bad "wired: $out"
FAKE_MUT="" gate probe-clean "$GN"; out="$(<"$TMP/out")"
[[ "$(sed -n 5p <<<"$out")" == "mutations: 0/unknown" && $rc -eq 1 ]] && ok "a script with no line reads 0/unknown" || bad "no line: $out"
FAKE_MUT="mutations: 3/3 extra" gate probe-clean "$GN"; out="$(<"$TMP/out")"
[[ "$(sed -n 5p <<<"$out")" == "mutations: 0/unknown" ]] && ok "a malformed line reads 0/unknown" || bad "malformed: $out"

FAKE_GAL="galleries: 5/6 (2 migrated)" FAKE_GAL_EXP=6 gate probe-clean "hunts-clean=2"; out="$(<"$TMP/out")"
[[ "$(sed -n 6p <<<"$out")" == "galleries: 5/6 (2 migrated)" && $rc -eq 1 ]] && ok "galleries: is its script's own line, migrated suffix kept" || bad "wired gal: $out"
FAKE_GAL="galleries: 6/6 (2 migrated)" FAKE_GAL_EXP=7 gate probe-clean "hunts-clean=2"; out="$(<"$TMP/out")"
[[ $rc -eq 1 ]] && ok "galleries 6/6 below its pinned --expected 7 is RED" || bad "gal pin: rc=$rc $out"
FAKE_HUNTS="hunts-clean: 1" gate probe-clean "galleries=1/1"; out="$(<"$TMP/out")"
[[ "$(sed -n 7p <<<"$out")" == "hunts-clean: 1" && $rc -eq 1 ]] && ok "hunts-clean: is hunts_gate.py --report's own count; 1 is RED" || bad "wired hunts: $out"
FAKE_HUNTS="hunts-clean: 2/2" gate probe-clean "galleries=1/1"; out="$(<"$TMP/out")"
[[ "$(sed -n 7p <<<"$out")" == "hunts-clean: 0" && $rc -eq 1 ]] && ok "a malformed hunts line reads 0" || bad "malformed hunts: $out"
echo "== all green (main() with STUBS patched at the Python level) =="
for exp in 4 3; do
  FAKE_HUNTS="hunts-clean: 2" FAKE_GAL="galleries: 1/1" FAKE_ROUNDS="rounds: 50/50" FAKE_GEN="generated: 300/300" FAKE_MUT="mutations: 3/3" FAKE_EXP=$exp AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" AIDEX_SPEC_CORPUS="$CORP" python3 - "$HERE" >"$TMP/out" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import invariant_gate as g
g.STUBS.update({"galleries": "1/1", "hunts-clean": "2"})
sys.exit(g.main([]))
PY
  rc=$?
  if [[ $exp == 4 ]]; then [[ $rc -eq 1 ]] && ok "3/3 below the pinned --expected 4 is RED" || bad "shrunk Y read green: $(<"$TMP/out")"
  else [[ $rc -eq 0 ]] && ok "3/3 at the pinned --expected 3 is green" || bad "pinned green: rc=$rc $(<"$TMP/out")"; fi
done
FAKE_HUNTS="hunts-clean: 2" FAKE_GAL="galleries: 1/1" FAKE_ROUNDS="rounds: 50/50" FAKE_GEN="generated: 300/300" FAKE_MUT="mutations: 1/1" AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" AIDEX_SPEC_CORPUS="$CORP" python3 - "$HERE" >"$TMP/out" 2>"$TMP/err" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import invariant_gate as g
g.STUBS.update({"galleries": "1/1", "hunts-clean": "2"})
sys.exit(g.main([]))
PY
rc=$?; out="$(<"$TMP/out")"
[[ $rc -eq 0 && "$(tail -n +2 <<<"$out" | tr '\n' ' ')" == "corpus: 1/1 generated: 300/300 rounds: 50/50 mutations: 1/1 galleries: 1/1 hunts-clean: 2 " ]] \
  && ok "every line at its minimum exits 0, no override suffix" || bad "green: rc=$rc $out $(cat "$TMP/err")"

echo "$PASS ok, $FAIL failed"
[[ $FAIL -eq 0 ]]
