#!/usr/bin/env bash
# test-eval-checkpoint-remedy.sh — a failing `claude -p` is a runner error, never a model FAIL.
# Layer: script integration with a stub `claude` on PATH (no model call, no cost).
# Run with: bash skills/conventions/scripts/test-eval-checkpoint-remedy.sh
set -uo pipefail
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/eval-checkpoint-remedy.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\necho "auth error: token expired" >&2\nexit 1\n' > "$TMP/bin/claude"
chmod +x "$TMP/bin/claude"

out="$(PATH="$TMP/bin:$PATH" TMPDIR="$TMP" bash "$SCRIPT" 2>"$TMP/err")"; rc=$?
[[ $rc -eq 3 ]] || fail "a failing claude -p must exit 3, got $rc"
grep -q "auth error: token expired" "$TMP/err" || fail "the runner's stderr was swallowed: $(cat "$TMP/err")"
[[ "$out" != *FAIL* && "$out" != *"met expectation"* ]] || fail "a runner failure was scored as a model result: $out"

if [[ $failures -gt 0 ]]; then printf '%d failure(s)\n' "$failures"; exit 1; fi
echo "OK — eval-checkpoint-remedy: a claude -p failure exits 3 with its stderr, unscored"
