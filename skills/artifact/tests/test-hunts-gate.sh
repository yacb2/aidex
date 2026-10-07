#!/usr/bin/env bash
# test-hunts-gate.sh — hunts_gate.py with FAKE sub-gates and a FAKE probe (seams AIDEX_HUNT_GENERATED,
# AIDEX_HUNT_ROUNDS, AIDEX_RENDER_PROBE, AIDEX_HUNT_PAGES, AIDEX_HUNT_SAMPLE, --state-dir), no browser, no real gates.
# Contract: a clean round raises N (round 0 never counts), a new class is appended with an EMPTY note and
# keeps every round dirty until a person fills the note, fresh seeds each round, a crashed / all-refused /
# wrong-count sub-run is dirty, pages with the same name are probed apart, --report runs nothing.
# Layer: script-level (the contract is the CLI's one stdout line and the two files it appends to).
# Run with: bash skills/artifact/tests/test-hunts-gate.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
H="$HERE/hunts_gate.py"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# fake gate: FAKE_<SUB>=ok | fail | crash | allrefused | wrongcount
cat > "$TMP/fake_gate.py" <<'PY'
import os, sys
sub = os.path.basename(sys.argv[0]).split("_")[0]          # generated_gate.py / rounds_gate.py
count = int(sys.argv[sys.argv.index("--count") + 1])
mode = os.environ.get("FAKE_" + sub.upper(), "ok")
open(os.environ["FAKE_LOG"], "a").write(sub + "\n")
open(os.environ["FAKE_SEEDS"], "a").write("%s %s\n" % (sub, sys.argv[sys.argv.index("--seed") + 1]))
if mode == "crash":
    sys.stderr.write("Traceback\n"); sys.exit(2)
built = 0 if mode == "allrefused" else count
if sub == "generated":
    sys.stderr.write("generated-gate: measured: builds: built %d, refused %d\n" % (built, count - built))
if mode == "fail":
    key = os.environ.get("FAKE_KEY", "INV:CNT-2")
    sys.stderr.write("CLASSES (x):\n     1  %s  seed 1\n" % key if sub == "generated"
                     else "class %s: 1 sequence(s), smallest seed 1\n" % key)
    print("%s: %d/%d" % (sub, count - 1, count)); sys.exit(1)
x = 0 if mode == "allrefused" and sub == "rounds" else count
y = count + 1 if mode == "wrongcount" else count
print("%s: %d/%d" % (sub, x, y)); sys.exit(0 if x == y else 1)
PY
mkdir -p "$TMP/gen" "$TMP/rnd"
cp "$TMP/fake_gate.py" "$TMP/gen/generated_gate.py"; cp "$TMP/fake_gate.py" "$TMP/rnd/rounds_gate.py"
cat > "$TMP/probe.sh" <<'SH2'
#!/usr/bin/env bash
# fake probe: PROBE_MODE=ok | viol | nosummary ; `viol` fires NAV-4 on the first page
shift; n=$#
echo x >> "$FAKE_LOG"; echo "$@" >> "$FAKE_PROBED"
case "${PROBE_MODE:-ok}" in
  nosummary) exit 0;;
  viol) if [[ -n "${PROBE_FIRE:-}" ]]; then v=0
          for pg in "$@"; do case " $PROBE_FIRE " in *" $(basename "$pg") "*) echo "INV NAV-4 $(basename "$pg") label"; v=$((v+1));; esac; done
          echo "INVARIANTS pages=$n violations=$v"; [[ $v -eq 0 ]]; exit $?
        fi
        echo "INV NAV-4 $(basename "$1") label"; echo "INVARIANTS pages=$n violations=1"; exit 1;;
  *) echo "INVARIANTS pages=$n violations=0"; exit 0;;
esac
SH2
mkdir -p "$TMP/pages"; echo '<p>plain</p>' > "$TMP/pages/a.html"; echo '<div class="consult-item"></div>' > "$TMP/pages/b.html"
export FAKE_SEEDS="$TMP/seeds" FAKE_PROBED="$TMP/probed" FAKE_LOG="$TMP/calls" AIDEX_HUNT_GENERATED="$TMP/gen/generated_gate.py" AIDEX_HUNT_ROUNDS="$TMP/rnd/rounds_gate.py" \
  AIDEX_RENDER_PROBE="$TMP/probe.sh" AIDEX_HUNT_PAGES="$TMP/pages"
: > "$TMP/calls"
fresh() { ST="$TMP/h$1"; unset FAKE_GENERATED FAKE_ROUNDS PROBE_MODE FAKE_KEY; }
n() { python3 "$H" --state-dir "$ST" 2>/dev/null; }
empty_note() { awk -F'\t' -v k="$1" -v r="$2" '$1==k && $2==r && NF==3 && $3=="" {f=1} END{exit !f}' "$ST/ledger.tsv"; }
status() { cut -f3 "$ST/rounds.tsv" | tail -1; }

echo "== clean rounds raise N; round 0 is the baseline and never counts; exit 0 only at 2 =="
fresh 1
o0="$(n)"; o1="$(n)"; rc1=$?; o2="$(n)"; rc2=$?
[[ "$o0" == "hunts-clean: 0" && "$o1" == "hunts-clean: 1" && $rc1 -eq 1 && "$o2" == "hunts-clean: 2" && $rc2 -eq 0 ]] \
  && ok "clean rounds 0,1,2 print 0,1,2 (round 0 uncounted), exit 1 then 0" || bad "got '$o0' '$o1' rc=$rc1, '$o2' rc=$rc2"

echo "== a new class is appended with an EMPTY note and stays dirty until a person fills it in =="
fresh 2
n >/dev/null; n >/dev/null
export PROBE_MODE=viol; o="$(n)"
[[ "$o" == "hunts-clean: 0" && "$(status)" == dirty ]] && ok "new class: N resets to 0, round dirty" || bad "got '$o' status=$(status)"
empty_note real:NAV-4:presentation 2 && ok "the key is appended with its first round and an empty note" || bad "ledger: $(cat "$ST/ledger.tsv")"
o="$(n)"; o="$(n)"
[[ "$o" == "hunts-clean: 0" && "$(status)" == dirty ]] && ok "an unexplained (empty-note) key keeps every later round dirty" || bad "unexplained key: '$o' status=$(status)"
[[ "$(wc -l < "$ST/ledger.tsv")" -eq 1 ]] && ok "a key already in the ledger is not appended again" || bad "ledger grew"
awk -F'\t' -v OFS='\t' '$1=="real:NAV-4:presentation" {$3="explained by a person"} {print}' "$ST/ledger.tsv" > "$ST/l.new" && mv "$ST/l.new" "$ST/ledger.tsv"
o="$(n)"; [[ "$o" == "hunts-clean: 1" && "$(status)" == clean ]] && ok "once the note is filled in the key is known: clean" || bad "after note: '$o' status=$(status)"
fresh 3; export FAKE_GENERATED=fail FAKE_KEY=BUILD:valid-refused; n >/dev/null
empty_note gen:BUILD:valid-refused 0 && ok "a generated class key is read from the CLASSES lines" || bad "gen key: $(cat "$ST/ledger.tsv")"
fresh 4; export FAKE_ROUNDS=fail FAKE_KEY=id-lost; n >/dev/null
empty_note rounds:id-lost 0 && ok "a rounds class key is read from the class lines" || bad "rounds key: $(cat "$ST/ledger.tsv")"

echo "== fresh seeds: every round uses seeds outside the gates' base ranges and different from the last round =="
fresh 8; : > "$TMP/seeds"; n >/dev/null; n >/dev/null
python3 - "$TMP/seeds" <<'PY2' && ok "seeds differ between rounds and avoid generated 20261007..20261306 / rounds 8008..8057" || bad "seed check failed: $(cat "$TMP/seeds")"
import sys
rows = [l.split() for l in open(sys.argv[1])]
g = [int(s) for sub, s in rows if sub == "generated"]; r = [int(s) for sub, s in rows if sub == "rounds"]
assert len(g) == 2 and len(r) == 2 and g[0] != g[1] and r[0] != r[1], rows
assert all(not 20261007 <= x <= 20261306 for x in g) and all(not 8008 <= x <= 8057 for x in r), rows
PY2

echo "== same-named pages are probed apart; pages modified since the last round are always probed =="
mkdir -p "$TMP/p2/x" "$TMP/p2/y"; echo a > "$TMP/p2/x/same.html"; echo b > "$TMP/p2/y/same.html"
fresh 9; : > "$TMP/calls"; AIDEX_HUNT_PAGES="$TMP/p2" n >/dev/null
[[ "$(grep -c '^x' "$TMP/calls")" -eq 2 ]] && ok "two pages with one basename take two probe calls" || bad "probe calls: $(grep -c '^x' "$TMP/calls")"
mkdir -p "$TMP/p3"; for f in a b c; do echo "$f" > "$TMP/p3/$f.html"; done
fresh 10; export AIDEX_HUNT_PAGES="$TMP/p3" AIDEX_HUNT_SAMPLE=1; n >/dev/null; sleep 1; touch "$TMP/p3/a.html" "$TMP/p3/b.html"; : > "$TMP/probed"; n >/dev/null
[[ "$(grep -o 'a.html' "$TMP/probed" | wc -l)" -ge 1 && "$(grep -o 'b.html' "$TMP/probed" | wc -l)" -ge 1 ]] \
  && ok "both modified pages are probed although the sample is 1" || bad "probed: $(cat "$TMP/probed")"
export AIDEX_HUNT_PAGES="$TMP/pages"; unset AIDEX_HUNT_SAMPLE

echo "== the hunt source drops backups, fragments, duplicate checkouts and galleries =="
T="$TMP/src"; mkdir -p "$T/.aidex-artifact-prev" "$T/_src" "$T/proj-wt-1" "$T/galleries" "$T/real"
for f in real/live.html .aidex-artifact-prev/prev.html _src/frag.html real/x.body.html proj-wt-1/dup.html galleries/g.html; do echo z > "$T/$f"; done
fresh 11; : > "$TMP/probed"; AIDEX_HUNT_PAGES="$T" n >/dev/null
grep -q 'live.html' "$TMP/probed" && ok "the live page is probed" || bad "live page missing: $(cat "$TMP/probed")"
for ex in prev.html frag.html x.body.html dup.html /g.html; do
  grep -q "$ex" "$TMP/probed" && bad "$ex was probed" || ok "$ex is excluded"; done

echo "== per-key kit evidence: a key on old kits only is noted mechanically in round 0; a live class is never auto-noted =="
K="$TMP/kit"; mkdir -p "$K"
printf '<meta name="artifact-kit" content="30">' > "$K/old.html"; printf '<meta name="artifact-kit" content="42">' > "$K/cur.html"
export AIDEX_HUNT_KIT_VERSION=42
fresh 12; PROBE_MODE=viol AIDEX_HUNT_PAGES="$K" PROBE_FIRE="old.html" n >/dev/null
awk -F'\t' '$1=="real:NAV-4:presentation" && $3=="old-kit only (kit 30..30, 0 current)" {f=1} END{exit !f}' "$ST/ledger.tsv" \
  && ok "old-kit-only key gets the mechanical note" || bad "ledger: $(cat "$ST/ledger.tsv")"
fresh 13; PROBE_MODE=viol AIDEX_HUNT_PAGES="$K" PROBE_FIRE="old.html cur.html" n >/dev/null
empty_note real:NAV-4:presentation 0 && ok "a key firing on a current-kit page keeps an empty note" || bad "ledger: $(cat "$ST/ledger.tsv")"
[[ "$(status)" == dirty ]] && ok "that live class leaves the round dirty" || bad "status $(status)"
fresh 14; PROBE_MODE=viol AIDEX_HUNT_PAGES="$K" PROBE_FIRE="cur.html" n >/dev/null
empty_note real:NAV-4:presentation 0 && ok "a current-kit-only key is not noted either" || bad "ledger: $(cat "$ST/ledger.tsv")"
fresh 15; PROBE_MODE=viol AIDEX_HUNT_PAGES="$K" PROBE_FIRE="none" n >/dev/null; PROBE_MODE=viol AIDEX_HUNT_PAGES="$K" PROBE_FIRE="old.html" n >/dev/null
empty_note real:NAV-4:presentation 1 && ok "after round 0 nothing is auto-noted (a sample proves nothing)" || bad "ledger: $(cat "$ST/ledger.tsv")"
unset AIDEX_HUNT_KIT_VERSION

echo "== no verdict is dirty, never clean, and never enters the ledger =="
for case in "FAKE_GENERATED=crash" "FAKE_ROUNDS=crash" "FAKE_GENERATED=allrefused" "FAKE_ROUNDS=allrefused" \
            "FAKE_GENERATED=wrongcount" "PROBE_MODE=nosummary"; do
  fresh "x-$case"; n >/dev/null; export "$case"; o="$(n)"
  [[ "$o" == "hunts-clean: 0" && "$(status)" == dirty ]] && ok "$case: dirty" || bad "$case: '$o' status=$(status)"
  case "$case" in *allrefused) sub="${case#FAKE_}"; sub="${sub%%=*}"; sub="$(tr A-Z a-z <<<"$sub")"
    grep -q "harness:$sub:all-refused" "$ST/rounds.tsv" && ok "$case: named as all-refused" || bad "$case: log says $(cut -f4 "$ST/rounds.tsv" | tail -1)";; esac
  [[ ! -s "$ST/ledger.tsv" ]] && ok "$case: harness key not in the ledger" || bad "$case: ledger got $(cat "$ST/ledger.tsv")"
done
fresh 5; n >/dev/null; mkdir "$TMP/empty"; o="$(AIDEX_HUNT_PAGES="$TMP/empty" n)"
[[ "$o" == "hunts-clean: 0" ]] && ok "no real pages to probe: dirty" || bad "empty page dir gave '$o'"

echo "== --report prints N and runs nothing =="
fresh 6; n >/dev/null; n >/dev/null; n >/dev/null; : > "$TMP/calls"
o="$(python3 "$H" --state-dir "$ST" --report)"; rc=$?
[[ "$o" == "hunts-clean: 2" && $rc -eq 0 && ! -s "$TMP/calls" && "$(wc -l < "$ST/rounds.tsv")" -eq 3 ]] \
  && ok "--report: line from the log, no sub-run, log untouched" || bad "report '$o' rc=$rc calls=$(wc -l < "$TMP/calls")"
fresh 7; o="$(python3 "$H" --state-dir "$ST" --report)"; [[ "$o" == "hunts-clean: 0" ]] && ok "--report with no log: 0" || bad "no log gave '$o'"

echo "== $PASS ok, $FAIL failed =="
[[ $FAIL -eq 0 ]]
