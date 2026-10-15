#!/usr/bin/env bash
# test-worklist-close-verification-reader.sh — worklist-close.sh keeps its own reduced
# copy of the `## Verification` table reader (it only needs owner rows); this pins that
# copy to backlog's close-item.sh verification_rows, so a table-shape fix landing in one
# copy only turns this red (LOOP-013 conventions-scripts-s25, owner decision Q14).
#
# Layer: script-level, bash. Both readers are awk programs inside shell scripts, so the
# test extracts each program from its script text (no edit to either, no execution of
# either script) and feeds the same fixture items through both.
#   worklist-close.sh : awk program emitting  what<US>proof  for owner rows
#   close-item.sh     : verification_rows()   emitting kind<US>what<US>proof for every row
# The contract compared: close-item's owner rows, projected to what<US>proof, equal
# worklist-close's output, row for row and in order.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS="$(cd "$HERE/../.." && pwd -P)"
# Overridable so the mutant check can point at a temp copy; production runs use the repo.
WL_CLOSE="${WL_CLOSE:-$SKILLS/conventions/scripts/worklist-close.sh}"
CLOSE_ITEM="${CLOSE_ITEM:-$SKILLS/backlog/scripts/close-item.sh}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wlvr.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# --- extract the two readers ---------------------------------------------------
python3 - "$WL_CLOSE" "$TMP/wl.awk" <<'PY' || { echo "FAIL: cannot extract the awk program from worklist-close.sh"; exit 1; }
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"awk '(BEGIN\{s=0\}[^']*)' \"\$f\"\)", t)
if not m:
    sys.exit(1)
open(sys.argv[2], "w").write(m.group(1))
PY
sed -n '/^verification_rows() {/,/^}/p' "$CLOSE_ITEM" > "$TMP/ci.sh"
[ -s "$TMP/ci.sh" ] || { echo "FAIL: cannot extract verification_rows from close-item.sh"; exit 1; }
# shellcheck disable=SC1090
. "$TMP/ci.sh"

wl_rows() { awk -f "$TMP/wl.awk" "$1"; }
ci_owner_rows() { verification_rows "$1" | awk -F'\037' '$1=="owner" { printf "%s\037%s\n", $2, $3 }'; }

# compare <label> <fixture-file>
compare() {
  local label="$1" f="$2" a b
  a="$(wl_rows "$f" | od -c)"; b="$(ci_owner_rows "$f" | od -c)"
  if [ "$a" != "$b" ]; then
    fail "$label: worklist-close and close-item read different owner rows"
    diff <(wl_rows "$f" | od -c) <(ci_owner_rows "$f" | od -c) | sed 's/^/    /'
  fi
  # a fixture that yields no owner row from either reader proves nothing about equality
  [ -n "$EXPECT_ROWS" ] && [ -z "$(ci_owner_rows "$f")" ] && fail "$label: fixture yields no owner row"
  return 0
}

item() {  # item <name> <body>  -> $TMP/<name>.md
  printf -- '---\nid: BL-1\n---\n# Item\n\n%s\n' "$2" > "$TMP/$1.md"
}

EXPECT_ROWS=1
item plain '## Verification

| kind | what | proof |
|---|---|---|
| test | unit | green |
| owner | pick the colour | blue |
| owner | read the page | |
| smoke | page | shot |'
compare "plain table" "$TMP/plain.md"

item aligned '## Verification

| kind | what | proof |
|:---|:---:|---:|
| owner | aligned separator | ok |'
compare "colon-aligned separator" "$TMP/aligned.md"

item empty-what '## Verification
| kind | what | proof |
|---|---|---|
| owner | | the answer |
| owner |  | |'
compare "empty what cell" "$TMP/empty-what.md"

item short-rows '## Verification
| owner | only what |
| owner |
| owner | what | proof'
compare "rows with missing cells and no trailing pipe" "$TMP/short-rows.md"

item extra-cells '## Verification
| owner | what | a | b | c |
| owner | what | has \| escaped | tail |'
compare "extra cells and a pipe inside the proof" "$TMP/extra-cells.md"

item whitespace '## Verification   
|   owner   |   padded what   |   padded proof   |   
	| owner | tab-indented row is not a table row | x |
 | owner | space-indented row is not a table row | x |
| owner | after the indented rows | y |'
compare "padding, trailing blanks on the heading, indented rows" "$TMP/whitespace.md"

item other-sections '## Notes
| owner | in notes, ignored | n |
## Verification extra
| owner | wrong heading, ignored | n |
## Verification
| owner | in the section | yes |
### Sub heading inside
| owner | sub heading does not end the section | still in |
## After
| owner | after the section, ignored | n |'
compare "section boundaries" "$TMP/other-sections.md"

item two-sections '## Verification
| owner | first | 1 |
## Middle
text
## Verification
| owner | second | 2 |'
compare "two Verification sections" "$TMP/two-sections.md"

item case-and-kinds '## Verification
| Owner | capitalised kind | x |
| OWNER | upper kind | x |
| owner | exact | x |
| owners | plural | x |
| kind | what | proof |'
compare "kind is matched exactly" "$TMP/case-and-kinds.md"

printf -- '---\nid: BL-1\n---\n## Verification\r\n| kind | what | proof |\r\n|---|---|---|\r\n| owner | crlf what | crlf proof |\r\n' > "$TMP/crlf.md"
compare "CRLF line endings" "$TMP/crlf.md"

printf -- '---\nid: BL-1\n---\n## Verification\n| owner | last line without newline | x |' > "$TMP/nonl.md"
compare "no trailing newline" "$TMP/nonl.md"

EXPECT_ROWS=""
item no-table '## Verification

Nothing here yet.'
compare "section without a table" "$TMP/no-table.md"
item no-section '## Plan
| owner | x | y |'
compare "no Verification section" "$TMP/no-section.md"

if [ "$failures" -gt 0 ]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — worklist-close's owner-row reader equals close-item's verification_rows on 13 fixture tables"
