#!/usr/bin/env bash
# test-usage-retro.sh — the two load-bearing invariants of the usage-retro miners
# (BL-132), against the hand-written corpus fixture.
#
# WHY THIS SUITE EXISTS. Both invariants were undefended. Provenance-gating lived
# in mine_items.py with nothing pinning it; the strict-span rule lived nowhere at
# all — it was applied by hand in the 2026-08-07 study's analysis and did not
# survive it. Whatever is only in a docstring gets rewritten away.
#
# Scenarios:
#   (a) an item named ONLY inside a tool_result attributes to nothing
#   (b) a real user prompt naming an item DOES attribute
#   (c) strict-span: prompt + 1 edit -> working
#   (d) strict-span: no prompt + 2 edits -> NOT working
#   (e) strict-span: no prompt + 3 edits -> working, and the SAME item's 2-edit
#       span falls the other way (one item, two spans, opposite verdicts)
#   (f) is_working_span() is a pure predicate, callable without a corpus
#   (g) roots are real parameters: a bogus projects-root yields an empty registry
#   (h) the roots reach mine_defect_proneness through M.configure()
#   (i) a rootless run refuses rather than mining a guessed default
#   (j) a BL id shared by two projects resolves inside its own project
#   (k) one malformed line skips the LINE, never the whole session
#   (l) a transcript root under a DIFFERENT user's home still resolves
#   (m) mine_items and mine_slow_tests share one runner vocabulary
#
# Run with: bash skills/aidex-audit/tests/test-usage-retro.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RETRO="$TESTS_DIR/../scripts/usage-retro"
FIXTURE="$TESTS_DIR/fixtures/usage-retro-corpus.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

read -r PROJ TX <<< "$(bash "$FIXTURE")"
OUT="$(mktemp -d)"
cleanup() { rm -rf "$PROJ" "$TX" "$OUT"; }
trap cleanup EXIT

report="$(python3 "$RETRO/mine_items.py" --projects-root "$PROJ" \
  --transcripts-root "$TX" --out "$OUT" --min-mentions 1 2>&1)"

echo "$report" | grep -q 'registry: 4 tracked items' \
  || fail "(setup) expected 4 registry items: $report"

# span_field <slug> <field> [session] — empty when no such span exists. The
# session argument matters: delta deliberately has two spans (one working, one
# not), so a slug-only lookup would silently depend on file iteration order.
span_field() {
  python3 -c '
import json, sys
want = sys.argv[4] if len(sys.argv) > 4 else ""
for line in open(sys.argv[1] + "/spans.jsonl"):
    s = json.loads(line)
    if s["slug"] == sys.argv[2] and (not want or s["session"] == want):
        print(s[sys.argv[3]]); break
' "$OUT" "$1" "$2" "${3:-}"
}

# ---------------------------------------------------------------------------
# (a) THE PROVENANCE GATE. backlog/00-index.md lists every item, so a session
#     that merely READ the index would otherwise get the whole register
#     attributed to it. A slug seen only in a tool_result must produce no span.
#
#     ON MUTATION-TESTING THIS ONE, because the obvious attempt reads as vacuous:
#     the gate in user_text() is TWO layers — an early return on any tool_result
#     block, and a join that keeps only `type: "text"` blocks. Removing either
#     alone changes nothing, because the other still blocks it, so a single-layer
#     mutation leaves this assertion green and looks like a dead test. It is not:
#     removing BOTH (the realistic rewrite — "fold tool output into user text")
#     makes this fail, verified 2026-08-07. Do not "fix" this test on the strength
#     of a one-layer mutation.
# ---------------------------------------------------------------------------
[[ -z "$(span_field 2026-01-02-beta working)" ]] \
  || fail "(a) an item named only inside a tool_result must not attribute"

# The session still exists and still edits files — the gate has to be about
# provenance, not about the session being empty.
grep -q 'unrelated.py' "$TX"/*/s2.jsonl \
  || fail "(a) fixture drift: s2 should carry an edit, or (a) proves nothing"

# ---------------------------------------------------------------------------
# (b) the same mechanism must still attribute a REAL user prompt, or (a) would
#     pass by attributing nothing at all.
# ---------------------------------------------------------------------------
[[ "$(span_field 2026-01-01-alpha prompt_mentions)" == "1" ]] \
  || fail "(b) a user prompt naming the item should attribute"

# ---------------------------------------------------------------------------
# (c)(d)(e) THE STRICT-SPAN RULE: a working session is a user prompt naming the
#     item, OR >=3 edits. Without it "sessions per item" inflates ~2x.
# ---------------------------------------------------------------------------
[[ "$(span_field 2026-01-01-alpha working)" == "True" ]] \
  || fail "(c) prompt-mention + 1 edit should be a working span"
[[ "$(span_field 2026-01-03-gamma edits)" == "2" && \
   "$(span_field 2026-01-03-gamma working)" == "False" ]] \
  || fail "(d) no prompt + 2 edits must NOT be a working span"
[[ "$(span_field 2026-01-04-delta edits s4.jsonl)" == "3" && \
   "$(span_field 2026-01-04-delta working s4.jsonl)" == "True" ]] \
  || fail "(e) no prompt + 3 edits should be a working span (the edit rule)"
# The same item's OTHER span is one edit short and must fall the other way.
[[ "$(span_field 2026-01-04-delta edits s5.jsonl)" == "2" && \
   "$(span_field 2026-01-04-delta working s5.jsonl)" == "False" ]] \
  || fail "(e) 2 edits on the same item must NOT be a working span"

echo "$report" | grep -q '2 working, 2 below the strict-span rule' \
  || fail "(e) the run should report the working/non-working split: $report"

# ---------------------------------------------------------------------------
# ONE MENTION PER RECORD. `mentions` was `+= len(hits)` — the count of ALL
# distinct tracked tokens named in a record, credited wholly to the single winner.
# So "close BL-166 and BL-172 together" gave BL-166 two mentions, and a record
# naming one item in BOTH its forms cleared the default --min-mentions gate of 2 on
# its own. Neither is an "attributed mention" of that item under the flag's own help
# text, and `--min-mentions` is what decides whether a span is emitted at all.
#
# s3's assistant text is exactly that shape: "Working on BL-903 / 2026-01-03-gamma"
# — two tokens, one item, one record, therefore one mention.
[[ "$(span_field 2026-01-03-gamma mentions)" == "1" ]] \
  || fail "(e2) two tokens naming ONE item in one record must count as one mention, got $(span_field 2026-01-03-gamma mentions)"

# ---------------------------------------------------------------------------
# (f) the rule is a predicate, not prose in a docstring. The boundary is 3.
# ---------------------------------------------------------------------------
out_f="$(python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
from mine_items import is_working_span as w
cases = [
    ({"prompt_mentions": 1, "edits": 0}, True),
    ({"prompt_mentions": 0, "edits": 2}, False),
    ({"prompt_mentions": 0, "edits": 3}, True),
    ({"prompt_mentions": 0, "edits": 0}, False),
]
bad = [c for c, want in cases if w(c) is not want]
print("BAD" if bad else "OK", bad)
' "$RETRO")"
[[ "$out_f" == OK* ]] || fail "(f) is_working_span boundary wrong: $out_f"

# ---------------------------------------------------------------------------
# (g) the roots must be real parameters. If --projects-root were ignored, every
#     scenario above would silently be measuring the author's real home
#     directory instead of the fixture — and would still look green.
# ---------------------------------------------------------------------------
EMPTY="$(mktemp -d)"
out_g="$(python3 "$RETRO/mine_items.py" --projects-root "$EMPTY" \
  --transcripts-root "$TX" --out "$OUT/g" --min-mentions 1 2>&1)"
rm -rf "$EMPTY"
echo "$out_g" | grep -q 'registry: 0 tracked items' \
  || fail "(g) --projects-root is not being honoured: $out_g"

# ---------------------------------------------------------------------------
# (i) and there is no default to fall back on. An unset root would glob "/*/"
#     and mine whatever is there — a wrong answer that reads like an answer.
# ---------------------------------------------------------------------------
out_i="$(env -u AIDEX_PROJECTS_ROOT python3 "$RETRO/mine_items.py" \
  --transcripts-root "$TX" --out "$OUT/i" 2>&1)"; rc_i=$?
[[ $rc_i -ne 0 ]] || fail "(i) a rootless run must not exit 0 (got $rc_i): $out_i"
echo "$out_i" | grep -q 'AIDEX_PROJECTS_ROOT' \
  || fail "(i) the rootless error should name the env var: $out_i"

# ---------------------------------------------------------------------------
# (h) the roots reach the consumers through M.configure(), not just mine_items.
#     A defect-proneness run over this corpus finds items but no bug items, so
#     it must say so rather than crash or read the real corpus.
# ---------------------------------------------------------------------------
out_h="$(python3 "$RETRO/mine_defect_proneness.py" --projects-root "$PROJ" \
  --transcripts-root "$TX" --denominator all --min-touches 1 2>&1)"
echo "$out_h" | grep -q 'base rate              : 0.0%' \
  || fail "(h) defect-proneness should see the fixture corpus (0% bug items): $out_h"
echo "$out_h" | grep -q 'items attributed       : 3' \
  || fail "(h) defect-proneness should attribute the same 3 items: $out_h"

# ---------------------------------------------------------------------------
# (j) CROSS-PROJECT ID COLLISION. `BL-NNN` ids are project-scoped — mine_items
#     builds `id_map` per project for exactly this reason, and in the real
#     workspace 178 ids are shared across projects. A token map built globally
#     resolves every mention to whichever project sorts LAST, so one project's
#     session is attributed to a stranger's item and that item's `type:` is
#     what decides the bug numerator.
#
#     The corpus is two projects, one shared id, opposite types, and a session
#     that belongs to the alphabetically FIRST project. Its own item is a task,
#     so the honest base rate is 0%; resolving to zz_ws's bug item makes it
#     100%. The assertion is on the rate rather than on a file name because the
#     rate is what the flagged ranking is normalized against.
# ---------------------------------------------------------------------------
CP="$(mktemp -d)"; CPTX="$(mktemp -d)"
cp_cleanup() { rm -rf "$CP" "$CPTX"; }
trap 'cleanup; cp_cleanup' EXIT

cp_item() {  # cp_item <project> <slug> <type>
  mkdir -p "$CP/$1/.context/backlog"
  cat > "$CP/$1/.context/backlog/$2.md" <<EOF
---
title: "Shared id, $3 in $1"
id: BL-901
status: done
created: 2026-02-01
updated: 2026-02-01
type: $3
---

# Shared id
EOF
}
cp_item aa_ws 2026-02-01-alpha-task task
cp_item zz_ws 2026-02-09-zulu-bug   bug

CPD="$CPTX/-Users-yoelacevedo-Documents-projects-aa-ws"
mkdir -p "$CPD"
{
  python3 -c 'import json; print(json.dumps({"type":"user","timestamp":"2026-02-01T00:00:00Z","message":{"content":"fix BL-901 please"}}))'
  python3 -c 'import json; print(json.dumps({"type":"assistant","timestamp":"2026-02-01T00:01:00Z","message":{"content":[{"type":"tool_use","name":"Edit","id":"t","input":{"file_path":"/home/u/Documents/projects/aa_ws/src/pay.py","old_string":"a","new_string":"b"}}]}}))'
} > "$CPD/c1.jsonl"

out_j="$(python3 "$RETRO/mine_defect_proneness.py" --projects-root "$CP" \
  --transcripts-root "$CPTX" --denominator typed --min-touches 1 2>&1)"
echo "$out_j" | grep -q 'items attributed       : 1  (bug 0)' \
  || fail "(j) a shared BL id must resolve inside its own project, not the last-sorted one: $out_j"
echo "$out_j" | grep -q 'base rate              : 0.0%' \
  || fail "(j) the base rate must come from aa_ws's own task item, not zz_ws's bug: $out_j"

# The control: zz_ws's own session DOES resolve to zz_ws's bug item, or (j)
# would pass by attributing nothing at all.
CPD2="$CPTX/-Users-yoelacevedo-Documents-projects-zz-ws"
mkdir -p "$CPD2"
cp "$CPD/c1.jsonl" "$CPD2/c1.jsonl"
out_j2="$(python3 "$RETRO/mine_defect_proneness.py" --projects-root "$CP" \
  --transcripts-root "$CPTX" --denominator typed --min-touches 1 2>&1)"
echo "$out_j2" | grep -q 'items attributed       : 2  (bug 1)' \
  || fail "(j) control: each project's own session should attribute its own item: $out_j2"

# ---------------------------------------------------------------------------
# (k) ONE MALFORMED LINE MUST NOT DISCARD A WHOLE SESSION. The parse was a list
#     comprehension inside `except Exception: continue`, so a single truncated
#     record dropped every item signal in the file — including files that had just
#     PASSED the `hits_in(raw)` token pre-filter, i.e. exactly the sessions known
#     to mention a tracked item. Every sibling reader in the package skips only the
#     bad record, so the codebase disagreed with itself about the same operation.
#
#     Not reachable from today's corpus (0 of 3,465 files parse-fail), so this
#     pins the divergence and the silence rather than an incident.
DIRTY="$(mktemp -d)"
DD="$DIRTY/-Users-yoelacevedo-Documents-projects-demo-ws"
mkdir -p "$DD"
{
  py_dirty_prompt() {
    python3 -c 'import json,sys; print(json.dumps({"type":"user","timestamp":"2026-01-01T00:00:00Z","entrypoint":"cli","origin":{"kind":"human"},"promptSource":"typed","message":{"role":"user","content":sys.argv[1]}}))' "$1"
  }
  py_dirty_prompt "trabajemos en BL-901 ahora"
  python3 -c 'import json; print(json.dumps({"type":"assistant","timestamp":"2026-01-01T00:01:00Z","message":{"content":[{"type":"tool_use","name":"Edit","id":"t","input":{"file_path":"/p/demo_ws/src/alpha.py","old_string":"a","new_string":"b"}}]}}))'
  printf '{"type":"user","message":{"role":"user","con'
} > "$DD/dirty.jsonl"

out_k="$(python3 "$RETRO/mine_items.py" --projects-root "$PROJ" \
  --transcripts-root "$DIRTY" --out "$OUT/k" --min-mentions 1 2>&1)"
rm -rf "$DIRTY"
grep -q 'demo_ws: 1 spans' <<<"$out_k" \
  || fail "(k) a truncated trailing line discarded the whole session: $out_k"
grep -qE 'skipped 1 unparseable line' <<<"$out_k" \
  || fail "(k) the skipped line must be COUNTED, not silently dropped: $out_k"

# ---------------------------------------------------------------------------
# (l) THE TRANSCRIPT PREFIX IS NOT THE AUTHOR'S HOME PATH. tx_dirs_for used to
#     strip the literal `-Users-yoelacevedo-Documents-projects-`, so on any
#     machine with a different user `core` kept the whole encoded path, matched
#     neither branch, and the function returned [] for EVERY project. The run then
#     reported its registry and wrote zero spans, and mine_defect_proneness said
#     "nothing to measure" — silent zeros dressed as results.
#
#     The fixture is the shared corpus with ONE variable changed: the username in
#     the transcript directory name. Everything else is identical, so a failure
#     here can only be the prefix.
ALT="$(mktemp -d)"
cp -R "$TX"/-Users-yoelacevedo-Documents-projects-demo-ws \
      "$ALT/-Users-alice-Documents-projects-demo-ws"
out_l="$(python3 "$RETRO/mine_items.py" --projects-root "$PROJ" \
  --transcripts-root "$ALT" --out "$OUT/l" --min-mentions 1 2>&1)"
rm -rf "$ALT"
grep -q 'registry: 4 tracked items' <<<"$out_l" \
  || fail "(l) fixture drift: the registry should be unchanged: $out_l"
grep -q 'demo_ws: 4 spans' <<<"$out_l" \
  || fail "(l) a transcript root under another user's home found no sessions: $out_l"

# ---------------------------------------------------------------------------
# (m) ONE RUNNER VOCABULARY. mine_items carried a narrower second copy of
#     mine_slow_tests' TESTCMD — no optional `run `, no yarn/tox/go/cargo — so a
#     session verifying with `npm run test` or `go test ./...` reported
#     test_runs=0 in spans.jsonl while the same commands landed in the >60s tail
#     analysis. `test_runs` is a documented headline output of this instrument.
#
#     Asserted as identity, not as a list of commands: a shared definition is the
#     only thing that cannot drift, and a per-command assertion would pass on two
#     copies that happen to agree today.
out_m="$(python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import mine_items as A, mine_slow_tests as B
same = A.TESTCMD.pattern == B.TESTCMD.pattern
runners = ["npm run test", "pnpm run test", "yarn test", "tox -e py311",
           "go test ./...", "cargo test", "pytest -q", "vitest run"]
missed = [c for c in runners if not A.TESTCMD.search(c)]
print("SAME" if same else "DIVERGED", "|", ",".join(missed) if missed else "-")
' "$RETRO" 2>&1)"
[[ "$out_m" == SAME* ]] \
  || fail "(m) the two runner vocabularies are not the same object: $out_m"
[[ "$out_m" == *"| -" ]] \
  || fail "(m) mine_items misses real test runners: $out_m"

# ---------------------------------------------------------------------------
# (n) FILE ATTRIBUTION IS THE FORWARD-FILL, NOT A CROSS PRODUCT.
#     mine_defect_proneness collected every item mentioned anywhere in a session
#     and every file edited anywhere in it, then emitted the cross product — under
#     an inline comment claiming it was "the same convention mine_items uses". It
#     was not. A session that mentions 10 items while editing 20 files marked all
#     20 as touched by all 10, so both `b` and `n` in `share = b/n` were inflated
#     toward the session-level bug rate and every file was smeared toward base:
#     the centrality artifact the module docstring says it eliminates.
#
#     The corpus below is the minimal discriminator. One session, in order:
#       mention a BUG item     -> edit bug_only.py
#       mention a TASK item    -> edit task_only.py
#     Forward-fill gives each file exactly one item, so bug_only.py is 100% and
#     task_only.py is 0%. The cross product gives BOTH files both items, so both
#     come out at 50% — and the two files become indistinguishable, which is the
#     defect stated as a number.
XP="$(mktemp -d)"; XT="$(mktemp -d)"
mkdir -p "$XP/mix_ws/.context/backlog"
xitem() {  # xitem <id> <slug> <type>
  cat > "$XP/mix_ws/.context/backlog/$2.md" <<EOF
---
title: "$2"
id: $1
status: done
created: 2026-03-01
updated: 2026-03-01
type: $3
---

# $2
EOF
}
xitem BL-801 2026-03-01-the-bug  bug
xitem BL-802 2026-03-02-the-task task

XD="$XT/-Users-yoelacevedo-Documents-projects-mix-ws"
mkdir -p "$XD"
xprompt() {
  python3 -c 'import json,sys; print(json.dumps({"type":"user","timestamp":sys.argv[2],"entrypoint":"cli","origin":{"kind":"human"},"promptSource":"typed","message":{"role":"user","content":sys.argv[1]}}))' "$1" "$2"
}
xedit() {
  python3 -c 'import json,sys; print(json.dumps({"type":"assistant","timestamp":sys.argv[2],"message":{"content":[{"type":"tool_use","name":"Edit","id":"t","input":{"file_path":sys.argv[1],"old_string":"a","new_string":"b"}}]}}))' "$1" "$2"
}
{
  xprompt "arreglemos BL-801 ahora"            "2026-03-01T10:00:00Z"
  xedit   "/h/Documents/projects/mix_ws/src/bug_only.py"  "2026-03-01T10:01:00Z"
  xprompt "ahora pasemos a BL-802"             "2026-03-01T11:00:00Z"
  xedit   "/h/Documents/projects/mix_ws/src/task_only.py" "2026-03-01T11:01:00Z"
} > "$XD/mix.jsonl"

out_n="$(python3 "$RETRO/mine_defect_proneness.py" --projects-root "$XP" \
  --transcripts-root "$XT" --denominator typed --min-touches 1 --ratio 1.0 2>&1)"
rm -rf "$XP" "$XT"

share_of() { awk -v f="$1" '$NF ~ f {print $1}' <<<"$out_n" | head -1; }
grep -q 'items attributed       : 2  (bug 1)' <<<"$out_n" \
  || fail "(n) both items should be attributed, one of them a bug: $out_n"
grep -q 'base rate              : 50.0%' <<<"$out_n" \
  || fail "(n) the base rate should be 50% (one bug of two items): $out_n"
[[ "$(share_of 'bug_only\.py')" == "100%" ]] \
  || fail "(n) bug_only.py should be 100% bug items, got '$(share_of 'bug_only\.py')': $out_n"
# task_only.py is BELOW the flag threshold, so it must not appear in the flagged
# list at all. Under the cross product it lands at 50% — the same as the other
# file — and the ranking stops distinguishing them.
[[ -z "$(share_of 'task_only\.py')" ]] \
  || fail "(n) task_only.py was flagged at $(share_of 'task_only\.py') — the cross product smeared the bug item onto it: $out_n"

# ---------------------------------------------------------------------------
# (o) mine_verification.py SMOKE CELL — promoted 2026-08-23 out of a gitignored
#     `.context/` (findings §8.10). Its old `agg.json` input has no producer, so
#     it now derives targets from items.jsonl + spans.jsonl (mine_items.py's own
#     output) via a --min-edits threshold, and takes --since for a forward
#     census window. Two checks: it runs end to end against the shared fixture,
#     and --since excludes rather than silently ignoring the window.
# ---------------------------------------------------------------------------
out_o="$(python3 "$RETRO/mine_verification.py" --projects-root "$PROJ" \
  --transcripts-root "$TX" --data-dir "$OUT" --min-edits 1 2>&1)"
echo "$out_o" | grep -q 'items analysed (real-usage, >=1 edits): 3' \
  || fail "(o) mine_verification did not run against the fixture: $out_o"

out_o2="$(python3 "$RETRO/mine_verification.py" --projects-root "$PROJ" \
  --transcripts-root "$TX" --data-dir "$OUT" --min-edits 1 --since 2099-01-01 2>&1)"; rc_o2=$?
[[ $rc_o2 -ne 0 ]] || fail "(o) --since 2099-01-01 should exclude everything and exit non-zero: $out_o2"
echo "$out_o2" | grep -q 'nothing to measure' \
  || fail "(o) an empty window should say so, not print zeroed stats: $out_o2"

# ---------------------------------------------------------------------------
# (p) mine_slow_tests.py --since. It had no window filter at all, which is the
#     constraint a forward census (BL-135) depends on — an unwindowed run mixes
#     the pre-change baseline back into the figure meant to be compared against
#     it. Two invocations, one before the cutoff, one after; --since must keep
#     only the second and report the first as excluded, not silently drop it.
# ---------------------------------------------------------------------------
SLOWTX="$(mktemp -d)/-Users-yoelacevedo-Documents-projects-slow-ws"
mkdir -p "$SLOWTX"
{
  python3 -c 'import json; print(json.dumps({"type":"assistant","timestamp":"2026-01-01T00:00:00Z","message":{"content":[{"type":"tool_use","name":"Bash","id":"t1","input":{"command":"pytest"}}]}}))'
  python3 -c 'import json; print(json.dumps({"type":"user","timestamp":"2026-01-01T00:01:05Z","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":[{"type":"text","text":"1 passed"}]}]}}))'
  python3 -c 'import json; print(json.dumps({"type":"assistant","timestamp":"2026-06-01T00:00:00Z","message":{"content":[{"type":"tool_use","name":"Bash","id":"t2","input":{"command":"pytest"}}]}}))'
  python3 -c 'import json; print(json.dumps({"type":"user","timestamp":"2026-06-01T00:01:10Z","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":[{"type":"text","text":"1 passed"}]}]}}))'
} > "$SLOWTX/s.jsonl"

out_p1="$(python3 "$RETRO/mine_slow_tests.py" --transcripts-root "$(dirname "$SLOWTX")" 2>&1)"
echo "$out_p1" | grep -q 'timed test invocations : 2' \
  || fail "(p) control: both invocations should count with no --since: $out_p1"

out_p2="$(python3 "$RETRO/mine_slow_tests.py" --transcripts-root "$(dirname "$SLOWTX")" --since 2026-03-01 2>&1)"
echo "$out_p2" | grep -q 'timed test invocations : 1' \
  || fail "(p) --since 2026-03-01 should keep only the later invocation: $out_p2"
echo "$out_p2" | grep -q '1 before 2026-03-01' \
  || fail "(p) the excluded pre-window invocation must be counted, not silently dropped: $out_p2"
rm -rf "$(dirname "$SLOWTX")"

# ---------------------------------------------------------------------------
# (q) mine_items --since: spans ending before the window are excluded and the
#     exclusion is announced, never silent (BL-206 — every other miner has one)
# ---------------------------------------------------------------------------
read -r PROJ TX <<< "$(bash "$FIXTURE")"
OUTQ="$(mktemp -d)"
python3 "$RETRO/mine_items.py" --projects-root "$PROJ" --transcripts-root "$TX" \
  --out "$OUTQ" --min-mentions 1 >/dev/null 2>&1
n_all="$(wc -l < "$OUTQ/spans.jsonl" | tr -d ' ')"
[[ "$n_all" -gt 0 ]] || fail "(q) control run produced no spans"
OUTQ2="$(mktemp -d)"
out_q="$(python3 "$RETRO/mine_items.py" --projects-root "$PROJ" --transcripts-root "$TX" \
  --out "$OUTQ2" --min-mentions 1 --since 2099-01-01 2>&1)"
n_fut="$(wc -l < "$OUTQ2/spans.jsonl" | tr -d ' ')"
[[ "$n_fut" -eq 0 ]] || fail "(q) --since 2099-01-01 should keep no span, got $n_fut"
echo "$out_q" | grep -q "before 2099-01-01" \
  || fail "(q) excluded pre-window spans must be counted out loud: $out_q"
rm -rf "$PROJ" "$TX" "$OUTQ" "$OUTQ2"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — usage-retro: provenance gate (tool_result attributes nothing, real prompt does), strict-span rule at the 3-edit boundary, predicate pinned, roots honoured end-to-end, rootless run refused, project-scoped id resolution, one bad line skips the line not the session, machine-independent transcript prefix, one shared runner vocabulary"
