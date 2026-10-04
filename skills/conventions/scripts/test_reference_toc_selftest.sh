#!/usr/bin/env bash
# Self-test for test_reference_toc.sh, table-driven: one fixture per rule, each run alone.
# Usage: bash skills/conventions/scripts/test_reference_toc_selftest.sh
#
# fixtures/reference-toc/pass/ files must give rc=0 and "1 files checked, 0 failing".
# fixtures/reference-toc/fail/ files must give rc=1 and a FAIL line carrying the row's reason.
# A fixture file without a row (or a row without a file) is itself a failure, so a rename
# or a swap goes red. ok-100-lines-no-contents is not checked at all (rc=1, nothing found).
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="$D/test_reference_toc.sh"
FX="$D/fixtures/reference-toc"
fails=0
bad() { echo "FAIL: $*"; fails=$((fails + 1)); }

# run_alone KIND NAME -> sets out, rc (gate run on a root holding only that fixture)
run_alone() {
  local tmp; tmp="$(mktemp -d)"; mkdir -p "$tmp/skills/x/references"
  cp "$FX/$1/skills/x/references/$2.md" "$tmp/skills/x/references/"
  out="$(bash "$GATE" "$tmp")"; rc=$?
  rm -rf "$tmp"
}

PASS_ROWS=(ok-basic ok-fenced-h2 ok-tilde-fence-with-backticks ok-long-fence ok-duplicate-h2
  ok-atx-only ok-indented-h2 ok-h1-h2-same-text ok-one-h2-h3-listed ok-three-h2-nested-h3
  ok-dup-slugger ok-three-h2-unlisted-h3 ok-h3-before-first-h2 ok-fence-closed-by-longer
  ok-fence-info-line-inside ok-dup-slug-registered ok-fence-indented-3 ok-backtick-info-not-a-fence ok-contents-at-line-40 ok-closing-hashes)

# "file|reason fragment"
FAIL_ROWS=(
  "no-contents-101|no \`## Contents\` heading within the first 40 lines"
  "no-contents-101-no-trailing-newline|no \`## Contents\` heading within the first 40 lines"
  "contents-at-line-41|within the first 40 lines"
  "contents-only-in-fence|within the first 40 lines"
  "broken-anchor|anchor #gone resolves to no heading"
  "unlisted-h2|is not linked in Contents"
  "unlisted-indented-h2|is not linked in Contents"
  "non-link-bullet|not a [text](#anchor) link"
  "entry-indented-4|not a [text](#anchor) link"
  "contents-then-paragraph|no bullet list"
  "unclosed-fence|unclosed code fence"
  "h2-h3s-unlisted|is not linked in Contents (files with fewer than 3 H2s list every H3)"
  "two-h2-unlisted-h3|is not linked in Contents (files with fewer than 3 H2s list every H3)"
  "h3-not-nested|must be indented 2 spaces in Contents"
  "h2-entry-nested|must be a top-level Contents entry"
  "h3-wrong-parent|nested under the wrong parent"
  "entries-out-of-order|not in document order"
  "entry-duplicated|not in document order"
  "first-entry-nested|first Contents entry must not be nested"
  "h1-h2-same-text-no-suffix|is not linked in Contents (its anchor is #bootstrap--investigate-verify-write-configenv-1)"
)

# Every fixture file has a row and every row has a file.
for kind in pass fail; do
  rows=(); [ $kind = pass ] && rows=("${PASS_ROWS[@]}") || for r in "${FAIL_ROWS[@]}"; do rows+=("${r%%|*}"); done
  for f in "$FX/$kind/skills/x/references/"*.md; do
    n="$(basename "$f" .md)"; known=0
    for r in "${rows[@]}" ok-100-lines-no-contents; do [ "$r" = "$n" ] && known=1; done
    [ $known -eq 1 ] || bad "$kind/$n.md has no row"
  done
  for r in "${rows[@]}"; do [ -f "$FX/$kind/skills/x/references/$r.md" ] || bad "row $r has no $kind fixture"; done
done

for n in "${PASS_ROWS[@]}"; do
  run_alone pass "$n"
  [ $rc -eq 0 ] || bad "$n: rc=$rc, expected 0: $out"
  [ "$out" = "reference-toc: 1 files checked, 0 failing" ] || bad "$n: unexpected output: $out"
done

run_alone pass ok-100-lines-no-contents
[ $rc -eq 1 ] || bad "ok-100-lines-no-contents: rc=$rc, expected 1 (nothing checked)"
grep >/dev/null -F "no reference files found under" <<<"$out" || bad "ok-100-lines-no-contents: it was checked"

for row in "${FAIL_ROWS[@]}"; do
  n="${row%%|*}"; reason="${row#*|}"
  if [ "$n" = "$row" ] || [ -z "$reason" ]; then bad "row '$row' has no '|reason'"; continue; fi
  run_alone fail "$n"
  [ $rc -eq 1 ] || bad "$n: rc=$rc, expected 1"
  grep >/dev/null -F -- "references/$n.md:" <<<"$out" || bad "$n: no FAIL line for it: $out"
  grep >/dev/null -F -- "$reason" <<<"$out" || bad "$n: FAIL line lacks '$reason': $out"
  grep >/dev/null -xF "reference-toc: 1 files checked, 1 failing" <<<"$out" || bad "$n: bad closing line"
done

# Zero files checked is a failure.
empty="$(mktemp -d)"; mkdir -p "$empty/skills"
out="$(bash "$GATE" "$empty")"; rc=$?
rmdir "$empty/skills" "$empty"
[ $rc -eq 1 ] || bad "empty root: rc=$rc, expected 1"
grep >/dev/null -F "no reference files found under" <<<"$out" || bad "empty root: missing message"

if [ $fails -eq 0 ]; then echo "selftest ok (${#PASS_ROWS[@]} pass rows, ${#FAIL_ROWS[@]} fail rows)"; else exit 1; fi
