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

# --- RETRO-19 / BL-217: the seeded ux playbook carries both checks -----------------
# Asserted against the SCAFFOLDED file, never against the template: grepping the
# template directly stays green if new-audit.sh ever stops seeding it, which is the
# checker-lies-by-omission shape the 2026-07-25 suite audit named.
PB="$M/00-methodology.md"
grep -q 'Text truncation' "$PB" \
  || fail "seeded ux playbook has no text-truncation check (BL-217)"
grep -qi 'table column headers' "$PB" \
  || fail "the truncation check does not name table column headers as a covered surface"
grep -qi 'tooltip' "$PB" || fail "the truncation check does not mention a tooltip"
grep -q 'Post-implementation style-consistency comparison' "$PB" \
  || fail "seeded ux playbook has no post-implementation style-consistency comparison"
grep -qi 'Name the reference in .index.md' "$PB" \
  || fail "the style comparison does not require naming a concrete reference"
# "Emitting drift as findings" needs an output contract, or the section is advice.
grep -q 'Drift becomes findings' "$PB" \
  || fail "the style comparison does not route drift into findings"
# The advanced-checks table was renumbered when truncation took #11; a stale 11 there
# would give the playbook two check 11s.
grep -q '^| 16 | \*\*Animation / motion\*\*' "$PB" \
  || fail "advanced checks were not renumbered after truncation took #11"

# --- legacy alias input normalizes to the same short methodology ---
bash "$SCRIPTS/new-audit.sh" ux-audit second-pass >/dev/null 2>&1 || fail "legacy alias ux-audit: exited non-zero"
[[ -d "$M/$TODAY-second-pass" ]] || fail "alias ux-audit did not normalize into audits/ux/"
[[ ! -d ".context/audits/ux-audit" ]] || fail "alias created a separate ux-audit/ folder"
bash "$SCRIPTS/new-audit.sh" ia-opportunities ai-scan >/dev/null 2>&1 || fail "legacy alias ia-opportunities: exited non-zero"
[[ -d ".context/audits/ai-opportunities/$TODAY-ai-scan" ]] || fail "ia-opportunities did not normalize to ai-opportunities/"

# --- hitl (BL-046): methodology seeded from the playbook; aliases normalize ---
# --- BL-217, a11y half: the manual AT sweep gains the same defect, WCAG list intact ---
bash "$SCRIPTS/new-audit.sh" a11y wcag-pass >/dev/null 2>&1 || fail "new a11y: exited non-zero"
A11Y=".context/audits/a11y/00-methodology.md"
[[ -f "$A11Y" ]] || fail "a11y 00-methodology.md not seeded"
grep -qi 'truncated text recoverable' "$A11Y" \
  || fail "seeded a11y playbook has no truncated-text check in the manual sweep"
awk '/^## Manual assistive technology sweep/{s=1} /^## Recording findings/{s=0} s' "$A11Y" \
  | grep -qi 'table column headers' \
  || fail "the a11y truncation bullet is not inside the Manual AT sweep section"
awk '/^## WCAG Level A \+ AA checks/{s=1} /^## Manual assistive/{s=0} s' "$A11Y" \
  | grep -qi 'truncated text recoverable' \
  && fail "the truncation bullet leaked into the numbered WCAG list, which stays strictly WCAG"

bash "$SCRIPTS/new-audit.sh" hitl release-signoff >/dev/null 2>&1 || fail "new hitl: exited non-zero"
H=".context/audits/hitl"
[[ -d "$H/$TODAY-release-signoff" ]] || fail "hitl run folder missing"
grep -q "Division of labor" "$H/00-methodology.md" 2>/dev/null || fail "hitl 00-methodology.md not seeded from the hitl playbook"
if grep -rn "{{" "$H" >/dev/null 2>&1; then fail "unsubstituted {{placeholders}} in hitl scaffold"; fi
bash "$SCRIPTS/new-audit.sh" guided-manual second-signoff >/dev/null 2>&1 || fail "alias guided-manual: exited non-zero"
[[ -d "$H/$TODAY-second-signoff" ]] || fail "alias guided-manual did not normalize into audits/hitl/"

# --- standalone one-shot: dated run at root, no boards ---
bash "$SCRIPTS/new-audit.sh" --standalone usage-retro-q3 >/dev/null 2>&1 || fail "--standalone: exited non-zero"
S=".context/audits/$TODAY-usage-retro-q3"
[[ -f "$S/index.md" ]] || fail "standalone run index.md missing at audits/ root"
[[ ! -f ".context/audits/00-inventory.md" ]] || fail "standalone must not create root boards"
grep -q "^title:" "$S/index.md" || fail "standalone index.md lacks front-matter"
if grep -n "{{" "$S/index.md" >/dev/null 2>&1; then fail "standalone index has unsubstituted placeholders"; fi

# --- the documented no-args status block must read what the scaffolder writes (BL-094) ---
# It read .context/audits/00-changelog.md, a root path new-audit.sh never creates,
# so a bare /aidex-audit silently printed nothing about methodology changes.
SKILL_DIR="$(cd "$SCRIPTS/.." && pwd -P)"
STATUS_BLOCK="$(awk '/^# Quick status \(when invoked with no args\):$/{f=1} f{print} f && /^fi$/{exit}' "$SKILL_DIR/SKILL.md")"
[[ -n "$STATUS_BLOCK" ]] || fail "could not extract the Quick status block from SKILL.md"
STATUS_OUT="$(CLAUDE_SKILL_DIR="$SKILL_DIR" bash -c "$STATUS_BLOCK" 2>&1)"
[[ "$STATUS_OUT" == *"ux/00-changelog.md"* ]] \
  || fail "no-args status block does not read the methodology changelog it scaffolded: $STATUS_OUT"

# --- duplicate run refused ---
bash "$SCRIPTS/new-audit.sh" ux login-redesign >/dev/null 2>&1 && fail "duplicate run should be refused"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — canon methodology scaffold, alias normalization, standalone one-shot, dup refusal"
