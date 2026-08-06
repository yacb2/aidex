#!/usr/bin/env bash
# test-escalation.sh — escalation writes CANON cross-refs (rebuild 2026-07-02):
#   - Escalated To cell = <type>/<filename> MARKER (never a markdown relative link)
#   - backlog entry origin_ref = audit/<methodology>/<run>/<finding-id>
#   - row flips to base vocab: done + ISO dates
#   - --loop path: loop-spec front-matter gains the origin_ref back-link
#
# Runs the real sibling scripts (aidex-backlog register, aidex-loop scaffold)
# from the repo checkout. Run with: bash skills/aidex-audit/tests/test-escalation.sh

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.context/audits/ux/2026-06-01-first-pass" "$TMP/.context/backlog" "$TMP/.context/loops"
cd "$TMP"
A=".context/audits"
TODAY="$(date +%F)"

cat > "$A/ux/00-inventory.md" <<'EOF'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| F-1 | bug | auth | Token stored in URL | open | P1 | 2026-06-01 | — | — |
| F-2 | gap | a11y | Contrast below AA across app | open | P2 | 2026-06-01 | — | — |
EOF
echo "# m" > "$A/ux/00-methodology.md"; echo "# c" > "$A/ux/00-changelog.md"
printf -- '---\ntitle: "UX first pass"\nstatus: done\ncreated: 2026-06-01\nupdated: 2026-06-01\nmethodology: ux\n---\n' > "$A/ux/2026-06-01-first-pass/index.md"
printf '# Findings\n\n- **F-1** token\n- **F-2** contrast\n' > "$A/ux/2026-06-01-first-pass/findings.md"

# --- escalate to backlog ---
bash "$SCRIPTS/escalate-finding.sh" F-1 >/dev/null 2>&1 || fail "escalate F-1 exited non-zero"
BL_FILE="$(ls .context/backlog/*.md 2>/dev/null | grep -v 00-index | head -1)"
[[ -n "$BL_FILE" ]] || fail "no backlog entry created"
if [[ -n "$BL_FILE" ]]; then
  grep -q '^origin_ref: audit/ux/2026-06-01-first-pass/F-1' "$BL_FILE" \
    || fail "backlog origin_ref: expected audit/ux/2026-06-01-first-pass/F-1, got: $(grep '^origin_ref' "$BL_FILE")"
fi
row="$(grep '| F-1 ' "$A/ux/00-inventory.md")"
printf '%s' "$row" | grep -q '| done |' || fail "row status should be done, row: $row"
printf '%s' "$row" | grep -qE 'backlog/[a-z0-9][a-z0-9-]*' || fail "Escalated To should carry a backlog/<filename> marker, row: $row"
if printf '%s' "$row" | grep -q '](' ; then fail "Escalated To must be a MARKER, not a markdown link: $row"; fi
if printf '%s' "$row" | grep -qE '\| [0-9]{8} \|'; then fail "row carries legacy YYYYMMDD date: $row"; fi
# the marker must resolve per the conventions validator (cross-ref lookup)
MARKER="$(printf '%s' "$row" | grep -oE 'backlog/[a-z0-9][a-z0-9._-]*' | head -1)"
CAND="${MARKER#backlog/}"
[[ -f ".context/backlog/$CAND" || -f ".context/backlog/$CAND.md" ]] || fail "marker $MARKER does not resolve to the created file"

# --- escalate to loop-spec (--loop): back-link in front-matter ---
bash "$SCRIPTS/escalate-finding-to-loop.sh" F-2 --loop >/dev/null 2>&1 || fail "escalate --loop F-2 exited non-zero"
LOOP_FILE="$(ls .context/loops/*.md 2>/dev/null | grep -v STATE | head -1)"
[[ -n "$LOOP_FILE" ]] || fail "no loop-spec created"
if [[ -n "$LOOP_FILE" ]]; then
  grep -q '^origin_ref: audit/ux/2026-06-01-first-pass/F-2' "$LOOP_FILE" \
    || fail "loop-spec front-matter lacks the origin_ref back-link, got: $(grep '^origin_ref' "$LOOP_FILE" || echo '(none)')"
fi
row2="$(grep '| F-2 ' "$A/ux/00-inventory.md")"
printf '%s' "$row2" | grep -q '| done |' || fail "F-2 status should be done, row: $row2"
printf '%s' "$row2" | grep -qE 'loop/[a-z0-9][a-z0-9._-]*' || fail "F-2 Escalated To should carry a loop/<filename> marker, row: $row2"
if printf '%s' "$row2" | grep -q '](' ; then fail "F-2 Escalated To must be a MARKER, not a markdown link: $row2"; fi

# --- the escalated tree still validates clean ---
bash "$SCRIPTS/validate-audit.sh" "$A" >/dev/null 2>&1 || fail "escalated tree should validate clean"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — canon markers, methodology-scoped origin_ref, loop back-link, base vocab + ISO"
