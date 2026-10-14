#!/usr/bin/env bash
# test-new-communication.sh — a scaffolded body.md ends exactly as its template ends,
# final newline included (BL-780). new-communication.sh kept a private render_template
# that read with `$(cat)` and wrote with `printf '%s'`, so meeting/call bodies (which go
# straight from render_template to disk) lost the template's final newline. sent/received
# were masked: inject_style rewrites the file through awk, which re-adds it.
# Q47 rows: a leading slug date is dropped (same date, different date + note, date-only and
# date-date refused, a mid-slug date untouched).
#
# Layer: the script itself, run in a temp project — the defect is in which render_template
# the script ends up calling, so only the real entry point observes it.
# Run with: bash skills/comm/tests/test-new-communication.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)/new-communication.sh"
FAILURES=0
fail() { printf 'FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/.git"

# Both templates end in `-->\n`; the rendered body must end in exactly that, so a lost
# newline and a doubled one both fail.
for kind in meeting call sent received; do
  body="$(cd "$ROOT" && NO_COLOR=1 bash "$SCRIPT" "$kind" "tail-$kind" 2>/dev/null)" \
    || { fail "$kind: scaffolding exited non-zero"; continue; }
  tail="$(tail -c 4 "$body"; printf x)"
  [[ "$tail" == $'-->\nx' ]] || fail "$kind: body.md does not end with the template's '-->\\n' (last bytes: ${tail%x})"
done

# A slug that already starts with a date (owner Q47, 2026-10-14): `call 2026-10-13-reunion`
# made `2026-10-13-2026-10-13-reunion/`. The slug's date prefix is stripped and only the
# entry's date is used; a different slug date earns a one-line stderr note naming both; a
# date-only slug is refused; a date that is not the prefix is part of the name.
TODAY="$(date +%Y-%m-%d)"
MEET="$ROOT/.context/communications/meetings"
# Usage: scaffold <slug>; sets RC and ERR (stderr).
scaffold() {
  local errf; errf="$(mktemp "${TMPDIR:-/tmp}/w8nc.XXXXXX")"
  (cd "$ROOT" && NO_COLOR=1 bash "$SCRIPT" call "$1" >/dev/null 2>"$errf"); RC=$?
  ERR="$(cat "$errf")"; rm -f "$errf"
}

scaffold "$TODAY-reunion"
[[ $RC -eq 0 && -d "$MEET/$TODAY-reunion" && ! -e "$MEET/$TODAY-$TODAY-reunion" ]] \
  || fail "same-date slug: expected meetings/$TODAY-reunion (rc=$RC; got: $(ls "$MEET" | tr '\n' ' '))"
# The note is for differing dates only; a same-date note would name $TODAY twice on a line.
# Path lines are excluded: the scaffolded path itself names the dates.
[[ -z "$(printf '%s\n' "$ERR" | grep -v communications/ | grep -E "$TODAY.*$TODAY")" ]] || fail "same-date slug: printed a date note: $ERR"

scaffold "2000-01-01-retro"
[[ $RC -eq 0 && -d "$MEET/$TODAY-retro" ]] \
  || fail "different-date slug: expected meetings/$TODAY-retro (rc=$RC; got: $(ls "$MEET" | tr '\n' ' '))"
note="$(printf '%s\n' "$ERR" | grep -v communications/ | grep -F 2000-01-01 | grep -F "$TODAY")"
[[ -n "$note" ]] || fail "different-date slug: no stderr line naming both 2000-01-01 and $TODAY: $ERR"

scaffold "$TODAY"
[[ $RC -ne 0 && "$ERR" == *"only a date"* ]] || fail "date-only slug: not refused with a clear message (rc=$RC): $ERR"
[[ ! -e "$MEET/$TODAY-$TODAY" && ! -e "$MEET/$TODAY-" ]] || fail "date-only slug: created an entry folder"

# A date followed by a date is still only a date once the prefix is stripped (review r1).
scaffold "$TODAY-$TODAY"
[[ $RC -ne 0 && "$ERR" == *"only a date"* ]] || fail "date-date slug: not refused with a clear message (rc=$RC): $ERR"
[[ ! -e "$MEET/$TODAY-$TODAY" && ! -e "$MEET/$TODAY-$TODAY-$TODAY" ]] || fail "date-date slug: created an entry folder"

scaffold "sprint-2000-01-01-recap"
[[ $RC -eq 0 && -d "$MEET/$TODAY-sprint-2000-01-01-recap" ]] \
  || fail "mid-slug date: expected meetings/$TODAY-sprint-2000-01-01-recap untouched (rc=$RC; got: $(ls "$MEET" | tr '\n' ' '))"
[[ -z "$(printf '%s\n' "$ERR" | grep -v communications/ | grep -F 2000-01-01)" ]] || fail "mid-slug date: printed a date note: $ERR"

if [[ $FAILURES -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$FAILURES"
  exit 1
fi
printf 'OK — new-communication.sh keeps the template final newline for all four kinds and uses one date when the slug carries one\n'
