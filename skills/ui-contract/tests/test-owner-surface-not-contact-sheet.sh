#!/usr/bin/env bash
# test-owner-surface-not-contact-sheet.sh — BL-705: after a UI fix the owner is handed the
# consultation artifact, never the internal contact sheet or a page built from it.
# Layer: text contract (the flow is prose; no script opens review.html).
set -u
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SKILL="$SKILL_DIR/SKILL.md"
HARNESS="$SKILL_DIR/references/01-harness-contract.md"
VERIFY="$SKILL_DIR/../../agents/verify-ui.md"
FAILURES=0
fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }

# 1. The visual-bug row hands the owner the consultation, and keeps the sheet internal.
row="$(grep -F '| A visual bug is being fixed |' "$SKILL")"
echo "$row" | grep -qF 'gallery consultation' || fail "visual-bug row does not hand the owner the consultation"
echo "$row" | grep -qF 'never opened for the owner' || fail "visual-bug row does not keep the contact sheet internal"

# 2. verify-ui no longer names the contact sheet as the owner's review surface.
grep -qF 'owner is the final reviewer of the contact sheet' "$VERIFY" && fail "verify-ui names the contact sheet as the owner's review"
grep -qF 'never open one' "$VERIFY" || fail "verify-ui does not forbid opening the contact sheet"

# 3. The harness contract states the same.
grep -qF "owner's call on the contact sheet" "$HARNESS" && fail "harness contract sends the owner to the contact sheet"
grep -qF "never opens one in the owner's browser" "$HARNESS" || fail "harness contract lacks the never-open rule"

if [ "$FAILURES" -eq 0 ]; then echo "PASS: owner surface is the consultation"; exit 0; fi
echo "FAIL: $FAILURES cell(s)"; exit 1
