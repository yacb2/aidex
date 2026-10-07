#!/usr/bin/env bash
# review-night-gate.sh must fail closed: each cell below is a ledger or repo state
# that a printout-only gate would report as done. Layer: the gate's own CLI against a
# throwaway git repo, because its evidence is git history and files on disk.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/review-night-gate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0; err() { echo "FAIL: $*" >&2; fail=1; }

WS="$TMP/ws"; R="$WS/repo"; L="$WS/.context/research/2026-10-07-artifact-module-review"
mkdir -p "$R" "$L" "$WS/.context/backlog"
git -C "$R" init -q; git -C "$R" config user.email t@t; git -C "$R" config user.name t
mkdir -p "$R/skills/artifact/references" "$R/skills/artifact/tests" "$R/skills/conventions/scripts" "$R/skills/ui-contract/tests"
big() { python3 -c "print('x' * $1)"; }
big 4000 > "$R/skills/artifact/references/03-spec-grammar.md"
big 4000 > "$R/skills/artifact/references/04-block-vocabulary.md"
{ echo '# ref'; echo '## Route S'; echo '```'; echo '## inside a fence'; echo '```'; big 4000; echo '## The quality loop'; big 9000; } \
  > "$R/skills/artifact/references/02-local-first-artifacts.md"
printf '#!/bin/bash\necho "  ui-contract  299 lines  ~ ${UI_TOKENS:-4800} tokens"\n' > "$R/skills/conventions/scripts/test_skill_budget.sh"
git -C "$R" add -A; git -C "$R" commit -qm base; BASE=$(git -C "$R" rev-parse HEAD)
echo t > "$R/skills/artifact/tests/t.sh"; echo 'a' > "$R/skills/artifact/x.py"
git -C "$R" add -A; git -C "$R" commit -qm fix; FIX=$(git -C "$R" rev-parse --short HEAD)
printf 'a\nb\nc\n' > "$R/skills/artifact/x.py"; git -C "$R" commit -qam simplify; SIMP=$(git -C "$R" rev-parse --short HEAD)
big 3000 > "$R/skills/artifact/references/04-block-vocabulary.md"; git -C "$R" commit -qam trim
echo 'exit 0' > "$R/skills/ui-contract/tests/test-gallery-rules-owner.sh"; git -C "$R" add -A; git -C "$R" commit -qm owner
git -C "$R" checkout -qb side; echo s > "$R/skills/artifact/tests/s.sh"; git -C "$R" add -A; git -C "$R" commit -qm side
SIDE=$(git -C "$R" rev-parse --short HEAD); git -C "$R" checkout -q -
touch "$WS/.context/backlog/2026-10-07-bl-900-thing.md"

H=$'partition\tlens\tid\tfile_line\tverdict\tseverity\taction\tref\tnote'
markers() { for p in A B C D; do for l in correctness simplify; do printf '%s\t%s\tRUN\t-\tRAN\t-\t-\twf\t-\n' $p $l; done; done; }
good() { echo "$H"; markers
  printf 'A\tcorrectness\tA1\tx.py:1\tCONFIRMED\thigh\tfixed\t%s\t-\n' "$FIX"
  printf 'B\tsimplify\tB1\tx.py:2\tCONFIRMED\tlow\tapplied\t%s\t-\n' "$SIMP"
  printf 'C\tcorrectness\tC1\tx.py:3\tCONFIRMED\tlow\tfiled\tBL-900\tneeds a design call\n'
  printf 'D\tcorrectness\tD1\tx.py:4\tPLAUSIBLE\tlow\tfiled\tBL-901\t-\n'; }
run() { out="$(AIDEX_REVIEW_LEDGER="$L/ledger.tsv" bash "$GATE" --repo "$R" --base "$BASE" "$@" 2>/dev/null)" && rc=0 || rc=$?; }
has() { grep -qxF "$1" <<<"$out" || err "$2: expected line '$1', got: $(tr '\n' '|' <<<"$out")"; }

# 1. no ledger: exit 2, nothing on stdout
out="$(AIDEX_REVIEW_LEDGER="$TMP/none.tsv" bash "$GATE" --repo "$R" 2>/dev/null)" && rc=0 || rc=$?
[ "$rc" = 2 ] && [ -z "$out" ] || err "missing ledger: rc=$rc out='$out'"

# 2. the passing ledger: exit 0 with the five lines
good > "$L/ledger.tsv"; run
[ "$rc" = 0 ] || err "good ledger exit $rc"
has "partitions: 4/4" good; has "confirmed: 3/3" good; has "simplify: 1 applied, net source LOC +2" good
has "bl-710: done (ui-contract SKILL.md ~4800 tokens)" good
[ "$(wc -l <<<"$out")" -eq 5 ] || err "good ledger: not five lines"
grep -q '^canon-load: [0-9]* -> [0-9]*$' <<<"$out" || err "canon-load line shape"
read -r t0 t1 < <(sed -n 's/^canon-load: \([0-9]*\) -> \([0-9]*\)$/\1 \2/p' <<<"$out")
[ "$t0" -gt "$t1" ] || err "fixture trim did not lower T ($t0 -> $t1)"
# 12k bytes of the three files plus the Route S body: ~3000. Less means a fenced
# `## ` line cut the slice short; more means it ran past `## The quality loop`.
[ "$t0" -ge 3000 ] && [ "$t0" -lt 4000 ] || err "T0 slice wrong: $t0, expected 3000..3999"

# 3. one lens marker missing: 3/4 and non-zero
good | grep -v $'^D\tsimplify\tRUN' > "$L/ledger.tsv"; run
has "partitions: 3/4" "missing marker"; [ "$rc" = 1 ] || err "missing marker exit $rc"

# 4. a fixed row whose commit touches no test is unresolved
good | sed "s/fixed\t$FIX/fixed\t$SIMP/" > "$L/ledger.tsv"; run
has "confirmed: 2/3" "fixed without test"; [ "$rc" = 1 ] || err "fixed without test exit $rc"

# 5. a fixed row whose commit is not in HEAD's history is unresolved
good | sed "s/fixed\t$FIX/fixed\t$SIDE/" > "$L/ledger.tsv"; run
has "confirmed: 2/3" "commit off HEAD"

# 6. filed with no backlog file, and filed with no reason, are unresolved
good | sed 's/BL-900/BL-902/' > "$L/ledger.tsv"; run
has "confirmed: 2/3" "filed, no BL file"
good | sed 's/needs a design call/ /' > "$L/ledger.tsv"; run
has "confirmed: 2/3" "filed, no reason"

# 7. T1 not below T0 fails
good > "$L/ledger.tsv"; run --base HEAD
[ "$rc" = 1 ] || err "T1 == T0 exit $rc"

# 8. budget over the cap, and owner test absent or red, keep bl-710 open
UI_TOKENS=5001 run; grep -q '^bl-710: failing' <<<"$out" || err "over cap not failing"; [ "$rc" = 1 ] || err "over cap exit $rc"
mv "$R/skills/ui-contract/tests/test-gallery-rules-owner.sh" "$TMP/o.sh"; run
grep -q '^bl-710: pending' <<<"$out" || err "absent owner test not pending"; [ "$rc" = 1 ] || err "absent owner exit $rc"
echo 'exit 1' > "$R/skills/ui-contract/tests/test-gallery-rules-owner.sh"; run
grep -q '^bl-710: failing' <<<"$out" || err "red owner test not failing"
mv "$TMP/o.sh" "$R/skills/ui-contract/tests/test-gallery-rules-owner.sh"

# 9. a malformed row fails the run
{ good; printf 'E\tcorrectness\tE1\n'; } > "$L/ledger.tsv"; run
[ "$rc" = 1 ] || err "malformed row exit $rc"

[ "$fail" = 0 ] && echo "OK — review-night-gate: 9 cells fail closed"
exit "$fail"
