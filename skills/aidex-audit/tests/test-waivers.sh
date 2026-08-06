#!/usr/bin/env bash
# validate-audit.sh consumes .context/.aidex-waivers (BL-050).
#
# Canon parity with validate.py (00-global.md §10.1): same file, same line
# format, same anchor semantics. Before this, 00-global.md had to carry a
# caveat that only validate.py read the store, so an accepted audit finding
# came back every single run with nowhere to record the acceptance.
#
# Invariants:
#   1. An unanchored waiver suppresses its finding from counts and exit code.
#   2. A waived finding is still REPORTED under `waived: N` — never dropped.
#   3. An anchored waiver holds only while the file's sha256 matches; editing
#      the file resurfaces the finding (the reversibility the ratchet needs).
#   4. Unparseable waiver lines are counted, not silently swallowed.
set -euo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATE="$SKILL/scripts/validate-audit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

AUD="$TMP/.context/audits"
INV="$AUD/ux/00-inventory.md"
mkdir -p "$AUD/ux"

# Two violations on purpose, one per shape:
#   audit-methodology-missing-board       -> path is a file that does NOT exist
#   audit-lifecycle-dropped-unreasoned    -> path is the inventory, so anchorable
cat > "$INV" <<'MD'
# UX inventory

| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| UX-1 | bug | login | button unreachable | dropped | medium | 1 | — | — |
MD
printf -- '# UX methodology\n' > "$AUD/ux/00-methodology.md"
# 00-changelog.md deliberately absent.

WAIVERS="$TMP/.context/.aidex-waivers"
run() { "$VALIDATE" "$AUD" >"$TMP/out" 2>&1 && echo 0 || echo $?; }
has_rule() { grep -q "($1)" "$TMP/out"; }
waived_line() { grep -oE 'waived: [0-9]+' "$TMP/out" | head -1; }

# ---- 1. baseline: both violations active, nothing waived -------------------
rc="$(run)"
[ "$rc" = "1" ] || err "clean-slate run exited $rc, expected 1 (two violations)"
has_rule audit-methodology-missing-board || err "missing-board violation not reported"
has_rule audit-lifecycle-dropped-unreasoned || err "dropped-unreasoned violation not reported"
[ -z "$(waived_line)" ] || err "reported a waived count with no waiver file"

# ---- 2. unanchored waiver suppresses, but still reports --------------------
cat > "$WAIVERS" <<'MD'
# accepted findings
audit-methodology-missing-board | .context/audits/ux/00-changelog.md | - | methodology predates the changelog board | 2026-08-06
MD
rc="$(run)"
[ "$rc" = "1" ] || err "one waiver of two violations exited $rc, expected 1"
has_rule audit-methodology-missing-board && err "waived violation is still counted as active"
[ "$(waived_line)" = "waived: 1" ] || err "expected 'waived: 1', got '$(waived_line)'"
grep -q 'audit-methodology-missing-board — .context/audits/ux/00-changelog.md' "$TMP/out" \
  || err "waived finding was suppressed without being reported"

# ---- 3. anchored waiver holds while the file is unchanged -----------------
if command -v shasum >/dev/null 2>&1; then
  digest="$(shasum -a 256 "$INV" | cut -c1-16)"
else
  digest="$(sha256sum "$INV" | cut -c1-16)"
fi
echo "audit-lifecycle-dropped-unreasoned | .context/audits/ux/00-inventory.md | sha256:$digest | accepted, row is historical | 2026-08-06" >> "$WAIVERS"
rc="$(run)"
[ "$rc" = "0" ] || { err "both violations waived but exited $rc, expected 0"; cat "$TMP/out" >&2; }
[ "$(waived_line)" = "waived: 2" ] || err "expected 'waived: 2', got '$(waived_line)'"

# ---- 4. editing the anchored file resurfaces the finding ------------------
printf '\n<!-- touched -->\n' >> "$INV"
rc="$(run)"
[ "$rc" = "1" ] || err "anchored file changed but the finding stayed waived (exit $rc)"
has_rule audit-lifecycle-dropped-unreasoned || err "resurfaced finding is not reported"
[ "$(waived_line)" = "waived: 1" ] || err "expected 'waived: 1' after anchor break, got '$(waived_line)'"

# ---- 5. unparseable lines are counted, not swallowed ----------------------
echo "this line has no fields at all" >> "$WAIVERS"
rc="$(run)"
grep -q 'waiver file: 1 unparseable line(s) ignored' "$TMP/out" \
  || err "unparseable waiver line was silently swallowed"

if [ "$fail" -eq 0 ]; then
  echo "OK: validate-audit.sh honors .aidex-waivers (suppress + report + anchor resurface + parse errors)"
fi
exit "$fail"
