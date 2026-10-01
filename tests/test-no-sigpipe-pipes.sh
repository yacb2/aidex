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
# Scope: skills/**/*.sh. EXCLUDED_PREFIXES lists paths another change is still
# converting; delete an entry when its sweep lands.
#
# Run with: bash tests/test-no-sigpipe-pipes.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
EXCLUDED_PREFIXES=(skills/artifact/ skills/conventions/scripts/close-dated-artifact.sh skills/conventions/scripts/test-close-dated-artifact.sh)

# Echo "file:line:text" for every unsafe pipe in the pipefail scripts under $1.
scan() {
  local root="$1" f ex skip
  while IFS= read -r f; do
    skip=0
    for ex in "${EXCLUDED_PREFIXES[@]}"; do [[ "$f" == "$ex"* ]] && skip=1; done
    [[ $skip -eq 1 ]] && continue
    grep >/dev/null -E '^[[:space:]]*set .*pipefail' "$root/$f" || continue
    grep -nE '(^|[^|])\|[[:space:]]*(grep[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*q|grep[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(-m|--max-count)|head([[:space:]]|$))' "$root/$f" \
      | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$f:|"
  done < <(cd "$root" && find skills -name '*.sh' | sort)
}

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# Cell 1: the detector flags each unsafe shape and passes the safe forms.
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/skills/x"
cat > "$FIX/skills/x/bad.sh" <<'EOS'
set -o pipefail
produce | grep -q needle
produce | grep -qiE 'a|b'
v="$(produce | head -1)"
EOS
cat > "$FIX/skills/x/good.sh" <<'EOS'
set -o pipefail
produce | grep >/dev/null needle
v="$(produce | sed -n 1p)"
a || grep -q needle file
EOS
cat > "$FIX/skills/x/nopipefail.sh" <<'EOS'
produce | grep -q needle
EOS
got="$(scan "$FIX")"
[[ "$(printf '%s\n' "$got" | grep -c '^skills/x/bad.sh:')" == 3 ]] || fail "detector should flag the 3 unsafe lines of bad.sh, got: $got"
printf '%s\n' "$got" | grep >/dev/null -E 'good.sh|nopipefail.sh' && fail "detector flagged a safe or non-pipefail file: $got"

# Cell 2: the real tree has none.
real="$(scan "$REPO_ROOT")"
[[ -z "$real" ]] || fail "pipefail script pipes into an early-exit reader (use the forms in this file's header):
$real"

if [[ $failures -eq 0 ]]; then echo "OK: no pipefail script pipes into grep -q / grep -m / head"; else exit 1; fi
