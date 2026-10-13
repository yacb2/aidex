#!/usr/bin/env bash
# Behavioural test for worklist-new.sh input handling (LOOP-013 w1-rs).
# Layer: script behaviour in a throwaway project (mktemp with its own .context/, so
# find_project_root never answers the live workspace). Pins: an existing work-list is
# never overwritten (c07), a slug is never empty or hyphen-terminated (c08), --ref kinds
# are the closed set (c35), --title that cannot round-trip is refused (c36).
# Run with: bash skills/conventions/scripts/test-worklist-new.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
NEW="$DIR/worklist-new.sh"
ROOT="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$ROOT"' EXIT
mkdir "$ROOT/.context"
cd "$ROOT"
WL="$ROOT/.context/worklists"
SKILLS="$(cd "$DIR/../.." && pwd -P)"
today="$(date +%F)"

pass=0; fail=0
ok()  { printf 'ok   — %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s\n' "$*" >&2; fail=$((fail+1)); }
count() { ls "$WL" 2>/dev/null | wc -l | tr -d ' '; }
reset() { rm -rf "$WL"; }

# --- c07: a second run with the same title the same day must not destroy the first
reset
f=$(bash "$NEW" --title "Run X" --ref "inline:a" 2>/dev/null)
printf 'TICKED-PROGRESS\n' >> "$f"
bash "$NEW" --title "Run X" --ref "inline:a" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ] && grep -q TICKED-PROGRESS "$f"; then ok "existing work-list is refused (rc 2) and left intact"
else bad "same-day same-title rerun: rc=$rc, progress kept: $(grep -c TICKED-PROGRESS "$f")"; fi

# --- c08: slug never empty, never ends in a hyphen
reset
bash "$NEW" --title '!!!' --ref "inline:a" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ] && [ "$(count)" -eq 0 ]; then ok "title with no ASCII alphanumerics is refused, no '<date>-.md' written"
else bad "empty-slug title: rc=$rc files=$(ls "$WL" 2>/dev/null)"; fi
bash "$NEW" --title '日本' --ref "inline:a" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ] && [ "$(count)" -eq 0 ]; then ok "non-ASCII title is refused"
else bad "non-ASCII title: rc=$rc files=$(ls "$WL" 2>/dev/null)"; fi
reset
a39=$(printf 'a%.0s' $(seq 1 39))
f=$(bash "$NEW" --title "$a39 b" --ref "inline:a" 2>/dev/null)
if [ "$(basename "$f")" = "$today-$a39.md" ]; then ok "slug cut at 40 chars does not end in a hyphen"
else bad "hyphen-terminated slug: got '$(basename "$f")'"; fi

# --- c35: --ref kind is one of backlog|plan|audit|inline
reset
for r in 'fix the thing' 'bogus:x' 'Backlog:BL-12' ':x' 'plans:x'; do
  bash "$NEW" --title "T $RANDOM" --ref "$r" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ]; then ok "--ref '$r' is refused"; else bad "--ref '$r' accepted (rc=$rc)"; fi
done
[ "$(count)" -eq 0 ] && ok "refused refs left no file behind" || bad "refused refs wrote: $(ls "$WL")"
f=$(bash "$NEW" --title "Kinds" --ref "backlog:BL-1 — a: b" --ref "plan:p" --ref "audit:r#1" --ref "inline:x" 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ] && grep -q '^1\. \[ \] BL-1 — a: b   <!-- ref: backlog -->$' "$f" \
   && python3 "$DIR/validate-worklist.py" "$f" >/dev/null 2>&1; then ok "the four kinds are accepted, label keeps its own colons, file validates"
else bad "valid kinds: rc=$rc"; fi

# --- c36: readers only strip quotes (no unescape), so " and \ are refused, not escaped
reset
for t in '"Q" run' 'a\b c'; do
  bash "$NEW" --title "$t" --ref "inline:a" --slug s36 >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ] && [ "$(count)" -eq 0 ]; then ok "title '$t' is refused (cannot round-trip through the readers)"
  else bad "title '$t': rc=$rc files=$(ls "$WL" 2>/dev/null)"; fi
done
reset
f=$(bash "$NEW" --title "Plain run: it's fine" --ref "inline:a" 2>/dev/null)
BACK="$SKILLS/backlog/scripts"
v=$(python3 -I - "$DIR/validate-worklist.py" "$f" <<'PY'
import sys, importlib.util
spec = importlib.util.spec_from_file_location("vw", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.parse_frontmatter(open(sys.argv[2]).read())["title"])
PY
)
r=$(python3 -I - "$BACK/sweep-report.py" "$f" <<'PY'
import sys, importlib.util
spec = importlib.util.spec_from_file_location("sr", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.fm_and_body(open(sys.argv[2]).read())[0]["title"])
PY
)
if [ "$v" = "Plain run: it's fine" ] && [ "$r" = "Plain run: it's fine" ]; then ok "title reads back unchanged through validate-worklist.py and sweep-report.py"
else bad "title parse-back: validator='$v' report='$r'"; fi
reset
bash "$NEW" --title $'two\nlines' --ref "inline:a" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ] && [ "$(count)" -eq 0 ]; then ok "a title with a newline is refused"
else bad "newline title: rc=$rc"; fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
