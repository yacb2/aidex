#!/usr/bin/env bash
# contract-night-gate's own test, on a synthetic census, fake scripts and fake
# fixtures (seams: AIDEX_SCRIPT_CENSUS, AIDEX_GATE_SCRIPTS, AIDEX_GATE_FIXTURES).
# Layer: script-level contract test; the gate is a CLI whose stdout/exit are the contract.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/contract-night-gate.sh"
fails=0
ok() { echo "  ok: $1"; }
bad() { echo "FAIL: $1"; fails=$((fails + 1)); }
check() { if [ "$2" = "1" ]; then ok "$1"; else bad "$1${3:+: $3}"; fi; }
eq() { check "$1" "$([ "$2" = "$3" ] && echo 1 || echo 0)" "got [$2] want [$3]"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
T=$'\t'

# mcase DIR SCRIPT ARGS STDIN EXPECT [CALLS_SCRIPT]: the one misuse case for id m1.
mcase() {
  printf 'id\tscript\targs\tstdin\texpect\nm1\t%s\t%s\t%s\t%s\n' "$2" "$3" "$4" "$5" > "$1/fx/misuse-replay/cases.tsv"
  awk -F'\t' -v OFS='\t' -v sc="${6:-$2}" '$11=="m1"{$4=sc}1' "$1/census/calls.tsv" > "$1/x" && mv "$1/x" "$1/census/calls.tsv"
}
# A scenario dir: census/, scripts/, fx/. Everything green by construction.
mkbase() {
  local d="$1" arm i b r
  mkdir -p "$d/census/bench" "$d/scripts/dash" "$d/fx/misuse-replay" "$d/fx/refusal-fixes" "$d/repo/skills/artifact/tests"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/repo/skills/artifact/tests/pass.sh"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$d/repo/skills/artifact/tests/fail.sh"
  : > "$d/fx/misuse-replay/a"
  printf 'date\tproject\tcaller\tscript\tcls\tnote\tretry\tstale\tcmd\terr\tid\n' > "$d/census/calls.tsv"
  printf 'id\tcheck\tdeliberate\n' > "$d/census/refusal-split.tsv"
  # 10 gate-refusals: A3 B3 C2 D1 E1 (A+B = exactly 60%)
  i=0
  for c in A A A B B B C C D E; do
    i=$((i + 1))
    printf '2026-10-01\tp\tmain\tcheck-artifact.sh\tgate-refusal\t\t0\t0\tc\te\tg%s\n' "$i" >> "$d/census/calls.tsv"
    printf 'g%s\t%s\t0\n' "$i" "$c" >> "$d/census/refusal-split.tsv"
  done
  printf '2026-10-01\tp\tmain\tx.sh\tok\t\t0\t0\tc\te\tok1\n' >> "$d/census/calls.tsv"
  printf '2026-10-01\tp\tmain\tsubst.sh\ttool-misuse\t\t0\t0\tc\te\tm1\n' >> "$d/census/calls.tsv"
  printf 'id\tclass\treason\nm1\ttool-misuse\tr\nq1\tother\tr\n' > "$d/census/review.tsv"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/scripts/ok.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$d/scripts/bad.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "Usage: usage.sh --foo FILE" >&2' 'exit 2' > "$d/scripts/usage.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "nothing helpful about foo" >&2' 'exit 2' > "$d/scripts/nousage.sh"
  printf '%s\n' 'import sys; sys.exit(0)' > "$d/scripts/dash/d.py"
  # observable substitution: {FIX} must be a real file path, {TMP}'s dir must exist
  printf '%s\n' '#!/usr/bin/env bash' '[ -f "$1" ] && [ -d "$(dirname "${2#--out=}")" ]' > "$d/scripts/subst.sh"
  mcase "$d" subst.sh '{FIX}/a --out={TMP}/a.html' '' accept subst.sh
  printf 'check\tkind\ttest_cmd\nA\tmessage\tbash skills/artifact/tests/pass.sh\nB\tautofix\tbash skills/artifact/tests/pass.sh\n' > "$d/fx/refusal-fixes/fixes.tsv"
  printf 'arm\tbrief\trep\tagent_id\tpages\trefusals\n' > "$d/census/bench/results.tsv"
  for b in b1 b2 b3 b4 b5 b6; do for r in 1 2 3; do
    printf 'main\t%s\t%s\tm-%s-%s\t10\t10\n' "$b" "$r" "$b" "$r" >> "$d/census/bench/results.tsv"
    printf 'branch\t%s\t%s\tb-%s-%s\t10\t7\n' "$b" "$r" "$b" "$r" >> "$d/census/bench/results.tsv"
  done; done
  printf '%s\n' 'import sys; sys.exit(0)' > "$d/census/census.py"
  printf '%s\n' 'import sys; sys.exit(0)' > "$d/census/report.py"
}
# Fake census.py/report.py that insist on their flags.
strict_stubs() {
  printf '%s\n' 'import sys,os' 'a=sys.argv; o=a[a.index("--out")+1]' \
    'open(os.path.join(o,"calls.tsv"),"w").write("x")' > "$1/census/census.py"
  printf '%s\n' 'import sys,os' 'p=sys.argv[sys.argv.index("--in")+1]' \
    'sys.exit(0 if os.path.isfile(p) else 3)' > "$1/census/report.py"
}

run() { # run DIR [args]; sets out err rc
  local d="$1"; shift
  out="$(AIDEX_SCRIPT_CENSUS="$d/census" AIDEX_GATE_SCRIPTS="$d/scripts" AIDEX_GATE_FIXTURES="$d/fx" AIDEX_GATE_REPO="$d/repo" \
    bash "$GATE" "$@" 2>"$tmp/err")"; rc=$?
  err="$(cat "$tmp/err")"
}
line() { printf '%s\n' "$out" | sed -n "${1}p"; }
scenario() { rm -rf "$tmp/$1"; mkbase "$tmp/$1"; S="$tmp/$1"; }

echo "== missing census: exit 2, one stderr line naming the variable, nothing on stdout =="
scenario base
: > "$tmp/afile"
for label in nonexistent afile no-calls no-review; do
  scenario "c-$label"
  case "$label" in
    nonexistent) cen="$tmp/nope" ;;
    afile) cen="$tmp/afile" ;;
    no-calls) rm "$S/census/calls.tsv"; cen="$S/census" ;;
    no-review) rm "$S/census/review.tsv"; cen="$S/census" ;;
  esac
  out="$(AIDEX_SCRIPT_CENSUS="$cen" bash "$GATE" 2>"$tmp/err")"; rc=$?; err="$(cat "$tmp/err")"
  eq "[$label] exit 2" "$rc" 2
  eq "[$label] stdout empty" "$out" ""
  check "[$label] one stderr line naming AIDEX_SCRIPT_CENSUS" \
    "$([ "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" -eq 1 ] && printf '%s' "$err" | grep >/dev/null AIDEX_SCRIPT_CENSUS && echo 1 || echo 0)" "$err"
done
check "[no-calls] names what is lacking" "$(printf '%s' "$(AIDEX_SCRIPT_CENSUS="$tmp/c-no-calls/census" bash "$GATE" 2>&1)" | grep >/dev/null 'lacks calls.tsv' && echo 1 || echo 0)"
check "[no-review] names what is lacking" "$(printf '%s' "$(AIDEX_SCRIPT_CENSUS="$tmp/c-no-review/census" bash "$GATE" 2>&1)" | grep >/dev/null 'lacks review.tsv' && echo 1 || echo 0)"

for label in calls-no-cls calls-no-script calls-no-id review-no-class; do
  scenario "col-$label"
  case "$label" in
    calls-no-cls) sed -i.bak '1s/\tcls\t/\tclsx\t/' "$S/census/calls.tsv" ;;
    calls-no-script) sed -i.bak '1s/\tscript\t/\tscriptx\t/' "$S/census/calls.tsv" ;;
    calls-no-id) sed -i.bak '1s/\tid$/\tidx/' "$S/census/calls.tsv" ;;
    review-no-class) sed -i.bak '1s/\tclass\t/\tclassx\t/' "$S/census/review.tsv" ;;
  esac
  run "$S"
  eq "F10 [$label] exit 2" "$rc" 2
  eq "F10 [$label] stdout empty" "$out" ""
  check "F10 [$label] one line naming the column" \
    "$([ "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" -eq 1 ] && printf '%s' "$err" | grep >/dev/null 'AIDEX_SCRIPT_CENSUS.*lacks column' && echo 1 || echo 0)" "$err"
done

echo "== everything green: five lines in order, exit 0 =="
scenario green; strict_stubs "$S"; run "$S"
eq "five lines" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 5
eq "line 1" "$(line 1)" "misuse: 1/1"
eq "line 2" "$(line 2)" "refusal-split: done"
eq "line 3" "$(line 3)" "top-refusals: 2/2"
eq "line 4" "$(line 4)" "bench: 1.00 -> 0.70"
eq "line 5" "$(line 5)" "census: rerun ok"
eq "exit 0" "$rc" 0

echo "== misuse =="
scenario mis-subst; run "$S"
eq "{FIX} and {TMP} are substituted (green case uses subst.sh)" "$(line 1)" "misuse: 1/1"
scenario mis-rc; mcase "$S" bad.sh '' '' accept
run "$S" --verbose
eq "accept with rc 1 is not matched" "$(line 1)" "misuse: 0/1"
eq "exit 1" "$rc" 1
check "verbose names the id and rc" "$(printf '%s' "$out" | grep >/dev/null 'm1: rc=1' && echo 1 || echo 0)" "$out"
scenario mis-nocase; printf 'id\tscript\targs\tstdin\texpect\n' > "$S/fx/misuse-replay/cases.tsv"
run "$S"; eq "id without a case counts against" "$(line 1)" "misuse: 0/1"
scenario mis-nofile; rm "$S/fx/misuse-replay/cases.tsv"
run "$S"; eq "missing cases.tsv counts against" "$(line 1)" "misuse: 0/1"
scenario mis-usage; mcase "$S" usage.sh '' '' 'usage:--foo'
run "$S"; eq "usage line plus substring matches" "$(line 1)" "misuse: 1/1"
scenario mis-usage-nosub; mcase "$S" usage.sh '' '' 'usage:--bar'
run "$S"; eq "usage present, substring absent: not matched" "$(line 1)" "misuse: 0/1"
scenario mis-usage-empty; mcase "$S" usage.sh '' '' 'usage:'
run "$S"; eq "F5 usage: with empty substring is invalid" "$(line 1)" "misuse: 0/1"
scenario mis-usage-otherline; printf '%s\n' '#!/usr/bin/env bash' 'echo "Usage: x" >&2' 'echo "the --foo flag" >&2' 'exit 2' > "$S/scripts/split.sh"
mcase "$S" split.sh '' '' 'usage:--foo'
run "$S"; eq "F5 substring on a later line than usage: is not matched" "$(line 1)" "misuse: 0/1"
scenario mis-parts; printf '%s\n' '#!/usr/bin/env bash' 'echo "usage: x.sh --a  -- missing --b" >&2' 'exit 2' > "$S/scripts/parts.sh"
mcase "$S" parts.sh '' '' 'usage:x.sh --a ;; missing --b'
run "$S"; eq "two ;; parts on one usage line: matched" "$(line 1)" "misuse: 1/1"
scenario mis-parts2; printf '%s\n' '#!/usr/bin/env bash' 'echo "usage: x.sh --a" >&2' 'echo "missing --b" >&2' 'exit 2' > "$S/scripts/parts2.sh"
mcase "$S" parts2.sh '' '' 'usage:x.sh --a ;; missing --b'
run "$S"; eq "a ;; part only on another line: not matched" "$(line 1)" "misuse: 0/1"
scenario mis-parts3; printf '%s\n' '#!/usr/bin/env bash' 'echo "usage: x.sh --a" >&2' 'exit 2' > "$S/scripts/parts3.sh"
mcase "$S" parts3.sh '' '' 'usage: ;; x.sh --a'
run "$S"; eq "an empty ;; part makes the case invalid" "$(line 1)" "misuse: 0/1"
scenario mis-nousage; mcase "$S" nousage.sh '' '' 'usage:foo'
run "$S"; eq "rc 2 and substring but no usage line: not matched" "$(line 1)" "misuse: 0/1"
scenario mis-dash; mcase "$S" dash/d.py '' '' accept
run "$S"; eq "dash/<name> .py runs under python3" "$(line 1)" "misuse: 1/1"
scenario mis-mjs; printf 'process.exit(0);\n' > "$S/scripts/m.mjs"; mcase "$S" m.mjs '' '' accept
if command -v node >/dev/null; then run "$S"; eq "F11 .mjs runs under node" "$(line 1)" "misuse: 1/1"; else echo "SKIP F11: no node"; fi
scenario mis-abs; mcase "$S" "$S/scripts/ok.sh" '' '' accept ok.sh
run "$S" --verbose; eq "F6 absolute script name refused" "$(line 1)" "misuse: 0/1"
scenario mis-dotdot; mkdir -p "$S/scripts/sub"; mcase "$S" sub/../ok.sh '' '' accept ok.sh
run "$S"; eq "F6 .. in the script name refused" "$(line 1)" "misuse: 0/1"
scenario mis-wrongscript; mcase "$S" ok.sh '' '' accept subst.sh
run "$S"; eq "F6 case script must be the census script of that id" "$(line 1)" "misuse: 0/1"
scenario mis-norm; mcase "$S" wrap_report.py '' '' accept wrap-report.sh
printf '%s\n' 'import sys; sys.exit(0)' > "$S/scripts/wrap_report.py"
run "$S"; eq "F6 wrap-report.sh in census matches wrap_report.py" "$(line 1)" "misuse: 1/1"
scenario mis-norm2; printf '%s\n' 'import sys; sys.exit(0)' > "$S/scripts/artifact_item.py"; mcase "$S" artifact_item.py '' '' accept artifact-item.sh
run "$S"; eq "F6 artifact-item.sh matches artifact_item.py" "$(line 1)" "misuse: 1/1"
scenario mis-nostdin; mcase "$S" ok.sh '' nope.txt accept ok.sh
run "$S" --verbose; eq "F9 missing stdin file is unmatched" "$(line 1)" "misuse: 0/1"
check "F9 no traceback, reason shown" "$(printf '%s' "$out $err" | grep >/dev/null 'Traceback' && echo 0 || echo 1)" "$out"
check "F9 reason names the stdin file" "$(printf '%s' "$out" | grep >/dev/null 'stdin file not found' && echo 1 || echo 0)"
scenario mis-stdin-ok; printf 'data\n' > "$S/fx/misuse-replay/in.txt"; printf '%s\n' '#!/usr/bin/env bash' 'grep -q data' > "$S/scripts/rd.sh"; mcase "$S" rd.sh '' in.txt accept rd.sh
run "$S"; eq "stdin file is piped" "$(line 1)" "misuse: 1/1"
scenario mis-X; printf 'id\tclass\treason\nm1\ttool-misuse\tr\nm2\ttool-misuse\tr\nm3\ttool-misuse\tr\n' > "$S/census/review.tsv"
run "$S"; eq "X is derived from review.tsv" "$(line 1)" "misuse: 1/3"
scenario mis-X0; printf 'id\tclass\treason\nq1\tother\tr\n' > "$S/census/review.tsv"
run "$S"; eq "F1 X == 0 reads unknown" "$(line 1)" "misuse: 0/unknown"; eq "F1 X == 0 exits 1" "$rc" 1
scenario mis-Xlow; printf '2026-10-01\tp\tmain\tsubst.sh\ttool-misuse\t\t0\t0\tc\te\tm9\n' >> "$S/census/calls.tsv"
run "$S"; eq "F1 X below calls.tsv tool-misuse count reads unknown" "$(line 1)" "misuse: 1/unknown"; eq "F1 exits 1" "$rc" 1

echo "== refusal-split =="
scenario sp-part; sed -i.bak '/^g10\t/d;/^g9\t/d' "$S/census/refusal-split.tsv"; printf 'g9\tunclear\t0\n' >> "$S/census/refusal-split.tsv"
run "$S"; eq "unclear and missing rows are not classified" "$(line 2)" "refusal-split: 8/10"; eq "exit 1" "$rc" 1
scenario sp-none; rm "$S/census/refusal-split.tsv"; run "$S"
eq "missing split reads unknown" "$(line 2)" "refusal-split: unknown"
eq "top-refusals unknown too" "$(line 3)" "top-refusals: unknown"
scenario sp-empty-check; sed -i.bak 's/^g1\tA/g1\t/' "$S/census/refusal-split.tsv"; run "$S"
eq "empty check is not classified" "$(line 2)" "refusal-split: 9/10"

echo "== top-refusals =="
scenario top-fail; printf 'check\tkind\ttest_cmd\nA\tmessage\tbash skills/artifact/tests/pass.sh\nB\tautofix\tbash skills/artifact/tests/fail.sh\n' > "$S/fx/refusal-fixes/fixes.tsv"
run "$S" --verbose; eq "a failing test_cmd does not count" "$(line 3)" "top-refusals: 1/2"; eq "exit 1" "$rc" 1
check "verbose names the check lacking a fix" "$(printf '%s' "$out" | grep >/dev/null 'without a passing fix: B' && echo 1 || echo 0)"
scenario top-nofix; printf 'check\tkind\ttest_cmd\n' > "$S/fx/refusal-fixes/fixes.tsv"
run "$S"; eq "no fixes at all" "$(line 3)" "top-refusals: 0/2"
scenario top-kind; printf 'check\tkind\ttest_cmd\nA\tmessage\tbash skills/artifact/tests/pass.sh\nB\tshrug\tbash skills/artifact/tests/pass.sh\n' > "$S/fx/refusal-fixes/fixes.tsv"
run "$S"; eq "F7 kind outside autofix|message|canon does not count" "$(line 3)" "top-refusals: 1/2"
scenario top-nofile; printf 'check\tkind\ttest_cmd\nA\tmessage\ttrue\nB\tcanon\tbash skills/artifact/tests/missing.sh\n' > "$S/fx/refusal-fixes/fixes.tsv"
run "$S"; eq "F7 test_cmd must name an existing test file" "$(line 3)" "top-refusals: 0/2"
scenario top-dotdot; printf 'check\tkind\ttest_cmd\nA\tmessage\tbash skills/artifact/tests/../tests/pass.sh\nB\tcanon\tbash tests/../skills/artifact/tests/pass.sh\n' > "$S/fx/refusal-fixes/fixes.tsv"
run "$S"; eq "F7 .. in the named file is refused" "$(line 3)" "top-refusals: 0/2"
scenario top-tests-root; mkdir -p "$S/repo/tests"; printf 'exit 0\n' > "$S/repo/tests/t.sh"; printf 'check\tkind\ttest_cmd\nA\tmessage\tbash tests/t.sh\nB\tcanon\tbash tests/t.sh\n' > "$S/fx/refusal-fixes/fixes.tsv"
run "$S"; eq "F7 a file under tests/ counts" "$(line 3)" "top-refusals: 2/2"
scenario top-all; printf 'check\tkind\ttest_cmd\nA\tmessage\tbash skills/artifact/tests/pass.sh\nA\tcanon\tbash skills/artifact/tests/fail.sh\nB\tautofix\tbash skills/artifact/tests/pass.sh\n' > "$S/fx/refusal-fixes/fixes.tsv"
run "$S"; eq "F7 a check passes only if ALL its rows pass" "$(line 3)" "top-refusals: 1/2"
scenario top-nar; sed -i.bak 's/^g6\tB/g6\tnot-a-refusal:x/;s/^g8\tC/g8\tnot-a-refusal:y/' "$S/census/refusal-split.tsv"   # A3 B2 C1 D1 E1 NAR2
run "$S"; eq "F8 not-a-refusal rows still count as classified" "$(line 2)" "refusal-split: done"
eq "F8 not-a-refusal rows leave the denominator (A+B=5 of 8)" "$(line 3)" "top-refusals: 2/2"
scenario top-nar2; sed -i.bak 's/^g\([6-9]\)\t[A-E]/g\1\tnot-a-refusal:x/' "$S/census/refusal-split.tsv"   # A3 B2 E1, NAR4 (one name)
run "$S"; eq "F8 not-a-refusal is never a counted check" "$(line 3)" "top-refusals: 2/2"
scenario top-deliberate; sed -i.bak 's/^g6\tB\t0/g6\tB\t1/;s/^g8\tC\t0/g8\tC\t1/' "$S/census/refusal-split.tsv"
run "$S"; eq "F8 deliberate rows stay in the denominator" "$(line 3)" "top-refusals: 2/2"
scenario top-allnar; sed -i.bak 's/^\(g[0-9]*\)\t[A-E]\t/\1\tnot-a-refusal:z\t/' "$S/census/refusal-split.tsv"
run "$S"; eq "F8 nothing left to fix reads unknown" "$(line 3)" "top-refusals: unknown"
scenario top-below; sed -i.bak 's/^g6\tB/g6\tC/' "$S/census/refusal-split.tsv"   # A3 B2 C3 D1 E1: A+C=6 -> still 2
run "$S"; eq "ties sort by name: A,C prefix" "$(line 3)" "top-refusals: 1/2"
scenario top-59; sed -i.bak 's/^g6\tB/g6\tD/;s/^g3\tA/g3\tE/' "$S/census/refusal-split.tsv"   # A2 B2 D2 E2 C2: 5 of 10 after two
run "$S"; eq "prefix needs >=60%: 3 checks when two reach only 40%" "$(line 3)" "top-refusals: 2/3"
scenario top-50; sed -i.bak 's/^g4\tB/g4\tA/;s/^g5\tB/g5\tA/' "$S/census/refusal-split.tsv"   # A5 B1 C2 D1 E1: 50% is not enough
run "$S"; eq "exactly 50% does not close the prefix" "$(line 3)" "top-refusals: 1/2"
scenario top-unreach; sed -i.bak '/^g10\t/d' "$S/census/refusal-split.tsv"; sed -i.bak 's/^g9\tD/g9\tunclear/;s/^g8\tC/g8\tunclear/;s/^g7\tC/g7\tunclear/;s/^g6\tB/g6\tunclear/;s/^g5\tB/g5\tunclear/' "$S/census/refusal-split.tsv"
run "$S"; eq "classified rows cannot reach 60% of all refusals" "$(line 3)" "top-refusals: 0/unknown"

echo "== bench =="
scenario b-17; sed -i.bak '$d' "$S/census/bench/results.tsv"; sed -i.bak '$d' "$S/census/bench/results.tsv"
# the last two rows were the 6th brief's 3rd rep for main and branch: both arms lose one row
run "$S"; eq "17 rows in each arm: unknown" "$(line 4)" "bench: unknown -> unknown"
scenario b-17b; grep -v '^branch.b6.3' "$S/census/bench/results.tsv" > "$S/x" && mv "$S/x" "$S/census/bench/results.tsv"
run "$S"; eq "only the short arm is unknown" "$(line 4)" "bench: 1.00 -> unknown"; eq "exit 1" "$rc" 1
scenario b-5briefs; sed -i.bak 's/^branch\tb6\t\([123]\)/branch\tb5\t\1x/' "$S/census/bench/results.tsv"
run "$S"; eq "18 rows but 5 briefs: unknown" "$(line 4)" "bench: 1.00 -> unknown"
scenario b-zero; awk -F'\t' -v OFS='\t' '$1=="main"&&$2=="b1"&&$3=="1"{$5=0}1' "$S/census/bench/results.tsv" > "$S/x" && mv "$S/x" "$S/census/bench/results.tsv"
run "$S"; eq "pages 0 row: arm unknown" "$(line 4)" "bench: unknown -> 0.70"
scenario b-none; rm -r "$S/census/bench"; run "$S"
eq "no results.tsv" "$(line 4)" "bench: unknown -> unknown"
scenario b-worse; awk -F'\t' -v OFS='\t' '$1=="branch"&&$2=="b1"&&$3=="1"{$6=8}1' "$S/census/bench/results.tsv" > "$S/x" && mv "$S/x" "$S/census/bench/results.tsv"
run "$S"; eq "A above 0.7B (0.71) shown" "$(line 4)" "bench: 1.00 -> 0.71"
eq "A > 0.7B exits 1 with all else green" "$rc" 1
eq "other lines still green" "$(line 1)|$(line 2)|$(line 3)" "misuse: 1/1|refusal-split: done|top-refusals: 2/2"
scenario b-exact; sed -i.bak 's/\t10\t10$/\t10\t30/;s/^\(branch.*\)\t10\t7$/\1\t10\t21/' "$S/census/bench/results.tsv"   # B=3.00, A=2.10 = 0.7*3 exactly (a float compare fails here)
run "$S"; eq "T4 A == 0.7B exactly passes" "$rc" 0; eq "T4 shows 3.00 -> 2.10" "$(line 4)" "bench: 3.00 -> 2.10"
scenario b-exact1; sed -i.bak 's/\t10\t10$/\t10\t30/;s/^\(branch.*\)\t10\t7$/\1\t10\t21/' "$S/census/bench/results.tsv"
awk -F'\t' -v OFS='\t' '$1=="branch"&&$2=="b1"&&$3=="1"{$6=22}1' "$S/census/bench/results.tsv" > "$S/x" && mv "$S/x" "$S/census/bench/results.tsv"
run "$S"; eq "T4 one refusal over 0.7B fails" "$rc" 1; eq "T4 shows 3.00 -> 2.11" "$(line 4)" "bench: 3.00 -> 2.11"
scenario b-nobase; sed -i.bak 's/\t10\t10$/\t10\t0/;s/^\(branch.*\)\t10\t7$/\1\t10\t0/' "$S/census/bench/results.tsv"
run "$S"; eq "F2 B == 0 is no baseline" "$(line 4)" "bench: 0.00 -> 0.00 (no baseline)"; eq "F2 exits 1 even with A == 0" "$rc" 1
scenario b-negref; awk -F'\t' -v OFS='\t' '$1=="branch"&&$2=="b1"&&$3=="1"{$6=-1}1' "$S/census/bench/results.tsv" > "$S/x" && mv "$S/x" "$S/census/bench/results.tsv"
run "$S"; eq "F3 negative refusals: that arm unknown" "$(line 4)" "bench: 1.00 -> unknown"
scenario b-negpages; awk -F'\t' -v OFS='\t' '$1=="main"&&$2=="b1"&&$3=="1"{$5=-3}1' "$S/census/bench/results.tsv" > "$S/x" && mv "$S/x" "$S/census/bench/results.tsv"
run "$S"; eq "F3 negative pages: that arm unknown" "$(line 4)" "bench: unknown -> 0.70"
scenario b-diffbriefs; sed -i.bak 's/^branch\tb6\t/branch\tb7\t/' "$S/census/bench/results.tsv"
run "$S"; eq "F4 different brief sets: both unknown" "$(line 4)" "bench: unknown -> unknown"
scenario b-reps; sed -i.bak 's/^branch\t\(b[1-6]\)\t3\t/branch\t\1\t4\t/' "$S/census/bench/results.tsv"
run "$S"; eq "F4 reps must be exactly 1,2,3" "$(line 4)" "bench: 1.00 -> unknown"
scenario b-pageseq; awk -F'\t' -v OFS='\t' '$1=="branch"&&$2=="b1"&&$3=="1"{$5=11}1' "$S/census/bench/results.tsv" > "$S/x" && mv "$S/x" "$S/census/bench/results.tsv"
run "$S"; eq "F4 pages per brief must match across arms" "$(line 4)" "bench: unknown -> unknown"
scenario b-ids; sed -i.bak 's/\tb-b[1-6]-[123]\t/\tsame\t/' "$S/census/bench/results.tsv"
run "$S"; eq "F4 36 distinct agent_ids required" "$(line 4)" "bench: unknown -> unknown"
scenario b-noid; sed -i.bak 's/\tm-b1-1\t/\t\t/' "$S/census/bench/results.tsv"
run "$S"; eq "F4 empty agent_id refused" "$(line 4)" "bench: unknown -> unknown"
scenario b-frac; sed -i.bak 's/\t10\t10$/\t30\t30/' "$S/census/bench/results.tsv"; sed -i.bak 's/^branch\(.*\)\t10\t7$/branch\1\t30\t21/' "$S/census/bench/results.tsv"
run "$S"; eq "ratio is sum/sum, not per row" "$(line 4)" "bench: 1.00 -> 0.70"

echo "== census rerun =="
scenario r-fail1; printf '%s\n' 'import sys; sys.exit(4)' > "$S/census/census.py"
run "$S"; eq "census.py failing" "$(line 5)" "census: rerun FAILED (census.py rc 4)"; eq "exit 1" "$rc" 1
scenario r-fail2; printf '%s\n' 'import sys; sys.exit(5)' > "$S/census/report.py"
run "$S"; eq "report.py failing" "$(line 5)" "census: rerun FAILED (report.py rc 5)"
scenario r-noflag; printf '%s\n' 'import sys' 'sys.exit(2 if "--out" in sys.argv else 0)' > "$S/census/census.py"
run "$S"; eq "census.py must accept --out" "$(line 5)" "census: rerun FAILED (census.py rc 2)"
scenario r-skip; strict_stubs "$S"; run "$S" --no-rerun
eq "--no-rerun" "$(line 5)" "census: skipped"; eq "--no-rerun exits non-zero" "$rc" 1
eq "--no-rerun keeps five lines" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 5

echo
if [ "$fails" -eq 0 ]; then echo "PASS: contract-night-gate"; else echo "FAILED: $fails"; exit 1; fi
