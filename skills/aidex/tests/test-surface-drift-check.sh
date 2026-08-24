#!/usr/bin/env bash
# test-surface-drift-check.sh — BL-222: the Claude Code surface reference and its drift check.
#
# Two properties matter more than "it can detect drift". The check must never PRESCRIBE
# a change — a newer Claude Code means unverified, not wrong, and prescribing from a
# version number reproduces the very defect this exists to catch. And it must never
# report "up to date" when it could not read a version at all, which is the silent-lie
# shape the 2026-07-25 suite audit named.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$DIR/scripts/surface-drift-check.py"
REF="$DIR/references/06-claude-code-surface.md"
FAILURES=0
fail() { printf 'FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$*"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- the shipped reference is parsable and covers what the acceptance names --------
OUT="$(python3 "$SCRIPT" --installed 9.9.9 2>&1)"; RC=$?
[[ $RC -eq 1 ]] || fail "a newer installed version must exit 1 (go look), got $RC"
for s in 'skillOverrides' 'MCP scoping' 'Plugin handling'; do
  grep -q "$s" <<<"$OUT" || fail "the reference does not record the '$s' surface: $OUT"
done
grep -q 'at risk:' <<<"$OUT" \
  || fail "drift output does not name which recommendation needs re-verifying"
pass "the shipped reference records skillOverrides, MCP scoping and plugin handling"

# --- read-only in the strong sense: it reports, it does not prescribe --------------
grep -qi 'does NOT mean the advice is wrong' <<<"$OUT" \
  || fail "drift output does not say a newer version means unverified, not wrong"
for verb in 'you should change' 'change it to' 'set it to' 'remove the'; do
  grep -qi "$verb" <<<"$OUT" && fail "the check prescribed a change ('$verb'): it must only say what to re-verify"
done
pass "reports what to re-verify and prescribes nothing"

# --- an equal or older installed version is clean ---------------------------------
OUT_OLD="$(python3 "$SCRIPT" --installed 0.0.1 2>&1)"; RC_OLD=$?
[[ $RC_OLD -eq 0 ]] || fail "an OLDER installed version must exit 0, got $RC_OLD"
grep -q 'nothing to re-verify' <<<"$OUT_OLD" || fail "older version was reported as drift: $OUT_OLD"
CURRENT="$(grep -o '| 2\.[0-9]*\.[0-9]* |' "$REF" | head -1 | tr -d '| ')"
OUT_EQ="$(python3 "$SCRIPT" --installed "$CURRENT" 2>&1)"; RC_EQ=$?
[[ $RC_EQ -eq 0 ]] || fail "the exact recorded version must exit 0, got $RC_EQ"
pass "equal or older installed version is clean; only newer asks for a look"

# --- partial drift: only the stale rows are named ---------------------------------
cat > "$TMP/partial.md" <<'EOF'
# Surface

## Surfaces

| Surface | Verified against | Recommendation that depends on it |
|---|---|---|
| old thing | 1.0.0 | something that would break |
| current thing | 5.0.0 | something else |

## Notes

| not a surface | 0.0.1 | this table is outside the section and must be ignored |
EOF
OUT_P="$(python3 "$SCRIPT" --reference "$TMP/partial.md" --installed 2.0.0 2>&1)"; RC_P=$?
[[ $RC_P -eq 1 ]] || fail "partial drift must exit 1, got $RC_P"
grep -q 'old thing' <<<"$OUT_P" || fail "the stale row was not named: $OUT_P"
grep -q 'current thing' <<<"$OUT_P" && fail "a row verified against a NEWER version was reported as stale"
grep -q 'not a surface' <<<"$OUT_P" && fail "a table outside '## Surfaces' was parsed as a surface row"
grep -q '1 of 2' <<<"$OUT_P" || fail "the count did not say 1 of 2: $OUT_P"
pass "only rows older than the installed version are named; other tables are not parsed"

# --- unreadable input is an error, never a clean report ---------------------------
python3 "$SCRIPT" --reference "$TMP/missing.md" --installed 2.0.0 >/dev/null 2>&1
[[ $? -eq 2 ]] || fail "a missing reference must exit 2, not report clean"
printf '# x\n\n## Surfaces\n\nno table here\n' > "$TMP/empty.md"
python3 "$SCRIPT" --reference "$TMP/empty.md" --installed 2.0.0 >/dev/null 2>&1
[[ $? -eq 2 ]] || fail "a reference with no rows must exit 2, not report clean"
printf '# x\n\n## Surfaces\n\n| Surface | Verified against | Recommendation |\n|---|---|---|\n| a | soon | b |\n' > "$TMP/bad.md"
python3 "$SCRIPT" --reference "$TMP/bad.md" --installed 2.0.0 >/dev/null 2>&1
[[ $? -eq 2 ]] || fail "a row with no parsable version must exit 2, not be skipped silently"
pass "missing, empty and unparsable references exit 2 rather than reading as clean"

# --- cannot read a version: say so, never claim up-to-date ------------------------
# A stub `claude` that prints no version, rather than emptying PATH — emptying it also
# hides python3, which made this cell fail for the wrong reason on first write.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/claude"
chmod +x "$TMP/bin/claude"
OUT_NC="$(PATH="$TMP/bin:$PATH" python3 "$SCRIPT" 2>&1)"; RC_NC=$?
[[ $RC_NC -eq 0 ]] || fail "an unreadable claude --version must exit 0, got $RC_NC"
grep -qi 'could not read' <<<"$OUT_NC" \
  || fail "with no CLI available the check must say nothing was compared: $OUT_NC"
grep -qi 'nothing to re-verify' <<<"$OUT_NC" \
  && fail "with no CLI available it claimed everything was up to date — the silent lie"
pass "with no readable CLI version it says nothing was compared, not 'up to date'"

# --- --json carries the same verdict ----------------------------------------------
python3 "$SCRIPT" --installed 9.9.9 --json "$TMP/out.json" >/dev/null 2>&1
python3 - "$TMP/out.json" <<'PY' || fail "--json does not carry the same verdict"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["installed"] == "9.9.9", d["installed"]
assert len(d["needs_reverification"]) == len(d["surfaces"]) >= 3
assert all({"surface", "verified_against", "depends"} <= set(s) for s in d["surfaces"])
PY
pass "--json emits the installed version, every surface, and the re-verify list"

if [[ $FAILURES -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$FAILURES"
  exit 1
fi
printf '\nOK — surface-drift-check: coverage, non-prescription, partial drift, bad input, no-CLI, json\n'
