#!/usr/bin/env bash
# test-no-sigpipe-pipes.sh — a script that sets pipefail must not pipe a producer
# into an early-exiting reader (BL-498).
#
# `producer | grep -q X` under pipefail: grep -q exits on the first match, the
# producer takes SIGPIPE (141) and the pipeline reads false although X was found.
# It flaked test-resolve-target.sh under load (aidex 57eead9). `| head -N` has the
# same shape. The safe forms read the whole stream:
#   grep -q PAT   ->  grep >/dev/null PAT      (same exit status, no early exit)
#   | head -N     ->  | sed -n 1,Np
# Scope: skills, tests and hooks (*.sh), this file excluded (it holds the pattern in strings). EXCLUDED_PREFIXES lists paths another change is still
# converting (none now besides this file); delete an entry when its sweep lands.
# Line-based scan: also flags a pipe at end of line with the reader on the next line.
#
# Run with: bash tests/test-no-sigpipe-pipes.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
EXCLUDED_PREFIXES=(tests/test-no-sigpipe-pipes.sh)

# A pipe (| or |&) into a reader that exits early: grep with -q/--quiet/--silent/-m/--max-count
# in any argument position, head, sed with a q command, awk with an exit that is not
# inside an END block. Perl (PCRE) because the quoted-string and word-boundary rules need
# lookahead. The argument span skips quoted strings and stops at an unquoted | ; ) &.
UNSAFE_READER='(?:^|[^|])\|&?\s*(?:grep\s(?:(?:[^|;)&\x27"]|\x27[^\x27]*\x27|"[^"]*")*\s)?(?:-[A-Za-z]*[qm][A-Za-z0-9]*|--quiet|--silent|--max-count)(?:[\s=]|$)|head(?:\s|$)|sed\s[^|;]*[0-9$/;{\s]q(?:[\s\x27"};]|$)|awk\s(?:[^|;)&\x27"]|\x27[^\x27]*\x27|"[^"]*")*?[\x27"]?(?:(?!\bEND\b)[^\x27"])*?\bexit\b)'

# A file counts as pipefail when it sets it or sources a sibling .sh that does.
has_pipefail() {
  local root="$1" f="$2" lib
  grep >/dev/null -E '^[[:space:]]*set .*pipefail' "$root/$f" && return 0
  while IFS= read -r lib; do
    [[ -n "$lib" && -f "$root/$(dirname "$f")/$lib" ]] \
      && grep >/dev/null -E '^[[:space:]]*set .*pipefail' "$root/$(dirname "$f")/$lib" && return 0
  done < <(sed -nE 's#^[[:space:]]*(source|\.)[[:space:]]+.*/([A-Za-z0-9_.-]+\.sh)["[:space:]]*$#\2#p' "$root/$f")
  return 1
}

# Echo "file:line:text" for every unsafe pipe in the pipefail scripts under $1.
scan() {
  local root="$1" f ex skip
  while IFS= read -r f; do
    skip=0
    for ex in "${EXCLUDED_PREFIXES[@]}"; do [[ "$f" == "$ex"* ]] && skip=1; done
    [[ $skip -eq 1 ]] && continue
    has_pipefail "$root" "$f" || continue
    # Join a line ending in a pipe (bare or backslash) with the next, so a reader on the
    # following line is seen; the joined line keeps the first line's number. A comment
    # line never starts a join.
    awk '{ l = $0; n = NR
           while (l !~ /^[ \t]*#/ && l ~ /[^|]\|&?[ \t]*\\?[ \t]*$/ && (getline nx) > 0) { sub(/[ \t]*\\?[ \t]*$/, "", l); l = l " " nx }
           print n ":" l }' "$root/$f" \
      | UNSAFE="$UNSAFE_READER" perl -ne 'print if /$ENV{UNSAFE}/' | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$f:|"
  done < <(cd "$root" && find skills tests hooks -name '*.sh' 2>/dev/null | sort)
}

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# Cell 1: the detector flags each unsafe shape and passes the safe forms.
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/skills/x" "$FIX/tests" "$FIX/hooks"
cat > "$FIX/skills/x/bad.sh" <<'EOS'
set -o pipefail
produce | grep -q needle
produce | grep -qiE 'a|b'
v="$(produce | head -1)"
produce |& grep -q needle
produce | grep --quiet needle
produce | grep -e needle -q
produce | grep -m1 x
produce | awk '/x/{print; exit}'
produce | sed 1q
produce |
  grep -q needle
produce | \
  grep -q needle
produce | grep -E 'a|b' -q
produce | awk '/PENDING/{print; exit}'
# usage: tool a|b|
produce | grep -q x
EOS
cat > "$FIX/skills/x/good.sh" <<'EOS'
set -o pipefail
produce | grep >/dev/null needle
v="$(produce | sed -n 1p)"
a || grep -q needle file
produce | awk '{a=$0} END{print a; exit}' | sed 's/a/b/'
produce | grep -c x
produce | sed 's/q/z/'
v="$(produce | awk '{print $2}')" || exit 1
produce | grep x && other -m 3
# produce | grep -q needle
EOS
cat > "$FIX/tests/bad.sh" <<'EOS'
set -o pipefail
produce | grep -q needle
EOS
cat > "$FIX/hooks/bad.sh" <<'EOS'
set -o pipefail
produce | grep -q needle
EOS
cat > "$FIX/skills/x/lib.sh" <<'EOS'
set -euo pipefail
EOS
cat > "$FIX/skills/x/sourcer.sh" <<'EOS'
. "$SCRIPT_DIR/lib.sh"
v="$(produce | head -1)"
EOS
cat > "$FIX/skills/x/nopipefail.sh" <<'EOS'
produce | grep -q needle
EOS
got="$(scan "$FIX")"
[[ "$(printf '%s\n' "$got" | grep -c '^skills/x/bad.sh:')" == 14 ]] || fail "detector should flag the 14 unsafe pipes of bad.sh, got: $got"
printf '%s\n' "$got" | grep >/dev/null '^skills/x/sourcer.sh:2:' || fail "detector missed a pipe in a script that sources a pipefail lib: $got"
for root in tests hooks; do
  printf '%s\n' "$got" | grep >/dev/null "^$root/bad.sh:" || fail "detector did not scan $root/: $got"
done
printf '%s\n' "$got" | grep >/dev/null -E 'good.sh|nopipefail.sh' && fail "detector flagged a safe or non-pipefail file: $got"

# Cell 2: the real tree has none.
real="$(scan "$REPO_ROOT")"
[[ -z "$real" ]] || fail "pipefail script pipes into an early-exit reader (use the forms in this file's header):
$real"

if [[ $failures -eq 0 ]]; then echo "OK: no pipefail script pipes into grep -q / grep -m / head"; else exit 1; fi
