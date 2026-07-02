#!/usr/bin/env bash
# test-scaffold.sh — new-audit.sh scaffolds the CANON layout (rebuild 2026-07-02):
#   - per-methodology folder with the three boards + dated run inside it
#   - short English methodology names (legacy forms normalize as aliases)
#   - NO unsubstituted {{PLACEHOLDER}} anywhere (the original reproduced bug)
#   - --standalone one-shot: dated run at audits/ root, no boards
#   - refuses a duplicate run
#
# Run with: bash skills/aidex-audit/tests/test-scaffold.sh

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.context"
cd "$TMP"
TODAY="$(date +%F)"

# --- methodology run: canon layout ---
bash "$SCRIPTS/new-audit.sh" ux login-redesign >/dev/null 2>&1 || fail "new ux: exited non-zero"
M=".context/audits/ux"
[[ -f "$M/00-inventory.md" && -f "$M/00-methodology.md" && -f "$M/00-changelog.md" ]] \
  || fail "canon boards missing under audits/ux/ (found: $(ls .context/audits 2>/dev/null | tr '\n' ' '))"
RUN="$M/$TODAY-login-redesign"
[[ -f "$RUN/index.md" && -f "$RUN/findings.md" ]] || fail "dated run folder incomplete: $RUN"
if grep -rn "{{" .context/audits/ >/dev/null 2>&1; then
  fail "unsubstituted {{placeholders}} in scaffold output: $(grep -rl '{{' .context/audits/ | tr '\n' ' ')"
fi
grep -q "^methodology: ux" "$RUN/index.md" || fail "run index.md front-matter lacks 'methodology: ux'"
for f in title status created updated; do
  grep -q "^$f:" "$RUN/index.md" || fail "run index.md missing front-matter field '$f'"
done

# --- legacy alias input normalizes to the same short methodology ---
bash "$SCRIPTS/new-audit.sh" ux-audit second-pass >/dev/null 2>&1 || fail "legacy alias ux-audit: exited non-zero"
[[ -d "$M/$TODAY-second-pass" ]] || fail "alias ux-audit did not normalize into audits/ux/"
[[ ! -d ".context/audits/ux-audit" ]] || fail "alias created a separate ux-audit/ folder"
bash "$SCRIPTS/new-audit.sh" ia-opportunities ai-scan >/dev/null 2>&1 || fail "legacy alias ia-opportunities: exited non-zero"
[[ -d ".context/audits/ai-opportunities/$TODAY-ai-scan" ]] || fail "ia-opportunities did not normalize to ai-opportunities/"

# --- standalone one-shot: dated run at root, no boards ---
bash "$SCRIPTS/new-audit.sh" --standalone usage-retro-q3 >/dev/null 2>&1 || fail "--standalone: exited non-zero"
S=".context/audits/$TODAY-usage-retro-q3"
[[ -f "$S/index.md" ]] || fail "standalone run index.md missing at audits/ root"
[[ ! -f ".context/audits/00-inventory.md" ]] || fail "standalone must not create root boards"
grep -q "^title:" "$S/index.md" || fail "standalone index.md lacks front-matter"
if grep -n "{{" "$S/index.md" >/dev/null 2>&1; then fail "standalone index has unsubstituted placeholders"; fi

# --- duplicate run refused ---
bash "$SCRIPTS/new-audit.sh" ux login-redesign >/dev/null 2>&1 && fail "duplicate run should be refused"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — canon methodology scaffold, alias normalization, standalone one-shot, dup refusal"
