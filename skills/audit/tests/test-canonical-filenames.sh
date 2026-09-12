#!/usr/bin/env bash
# test-canonical-filenames.sh — verify validate-audit.sh accepts both 00-* and legacy canonical filenames.
# Covers the four cases the backlog item asked for:
#   1. Only 00-prefixed files present       → pass, no warnings
#   2. Only legacy uppercase files present  → pass, no warnings
#   3. Both forms present                   → pass, warnings for each duplicate
#   4. Neither form present                 → fail, one violation per missing canonical
#
# Run: bash skills/audit/tests/test-canonical-filenames.sh
# Exit: 0 if all four pass, 1 if any case fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="$SCRIPT_DIR/../scripts/validate-audit.sh"
[[ -x "$VALIDATE" ]] || chmod +x "$VALIDATE"

# Minimal INVENTORY body that parses as canonical (header + one finding row).
INVENTORY_BODY='# Inventory

| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| BUG-CORE-1 | bug | core | sample finding | open | P2 | 20260515-fixture | — | — |
'

METHODOLOGY_BODY='# Methodology

Sample methodology body.
'

CHANGELOG_BODY='# Changelog

Sample changelog body.
'

PASS=0
FAIL=0
RESULTS=()

run_case() {
  local name="$1"; shift
  local expect_exit="$1"; shift
  local expect_warns_regex="$1"; shift
  local setup_fn="$1"; shift

  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.context/audits"
  "$setup_fn" "$tmp/.context/audits"

  # Always include a run subfolder so check 2 has something to look at.
  mkdir -p "$tmp/.context/audits/20260515-fixture"
  printf '# Index\n' > "$tmp/.context/audits/20260515-fixture/index.md"
  printf '# Findings\n\nBUG-CORE-1: see inventory.\n' > "$tmp/.context/audits/20260515-fixture/findings.md"

  local out exit_code
  out="$(NO_COLOR=1 bash "$VALIDATE" "$tmp/.context/audits" 2>&1)"
  exit_code=$?

  local ok=1
  if [[ "$exit_code" -ne "$expect_exit" ]]; then
    ok=0
    RESULTS+=("FAIL [$name]: expected exit $expect_exit, got $exit_code")
  fi
  if [[ -n "$expect_warns_regex" ]] && ! grep -qE "$expect_warns_regex" <<<"$out"; then
    ok=0
    RESULTS+=("FAIL [$name]: output did not match regex '$expect_warns_regex'")
  fi
  if [[ "$ok" -eq 1 ]]; then
    PASS=$((PASS+1))
    RESULTS+=("PASS [$name]")
  else
    FAIL=$((FAIL+1))
    RESULTS+=("---- output for [$name] ----")
    while IFS= read -r line; do RESULTS+=("    $line"); done <<<"$out"
    RESULTS+=("---- end output ----")
  fi

  rm -rf "$tmp"
}

setup_modern_only() {
  local d="$1"
  printf '%s' "$INVENTORY_BODY"  > "$d/00-inventory.md"
  printf '%s' "$METHODOLOGY_BODY" > "$d/00-methodology.md"
  printf '%s' "$CHANGELOG_BODY"   > "$d/00-changelog.md"
}

setup_legacy_only() {
  local d="$1"
  printf '%s' "$INVENTORY_BODY"  > "$d/INVENTORY.md"
  printf '%s' "$METHODOLOGY_BODY" > "$d/METHODOLOGY.md"
  printf '%s' "$CHANGELOG_BODY"   > "$d/CHANGELOG.md"
}

setup_both() {
  setup_modern_only "$1"
  setup_legacy_only "$1"
}

setup_neither() {
  : # no canonical files
}

run_case "modern-only"  0 ""                                  setup_modern_only
run_case "legacy-only"  0 ""                                  setup_legacy_only
run_case "both-forms"   0 "both 00-inventory.md and INVENTORY.md exist" setup_both
# Rebuild 2026-07-02 (ADR audit-rebuild-canon-decisions): no boards at the root
# is CANON now — a dated folder there is a standalone one-shot run, never a
# "missing canonical file" violation. The legacy YYYYMMDD name only warns.
run_case "neither-form" 0 "legacy YYYYMMDD naming" setup_neither

printf '\n'
for r in "${RESULTS[@]}"; do
  printf '%s\n' "$r"
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
