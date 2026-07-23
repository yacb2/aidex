#!/usr/bin/env bash
# test-tier2-e2e-contract.sh — verifies the Tier-2-includes-E2E-by-default
# contract is present on all canon surfaces + the user-installed rule file.
#
# Contract: Tier 2 = full isolation including isolated E2E capability by
# default: worktree_up must leave a runnable per-worktree test-e2e.sh with no
# additional ask.
#
# Run with: bash tests/test-tier2-e2e-contract.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

check_file() {
  local path="$1"
  local label="$2"

  if [ ! -f "$path" ]; then
    fail "$label: file not found ($path)"
    return
  fi

  if ! grep -q "by default" "$path"; then
    fail "$label: missing 'by default' phrasing ($path)"
  fi

  if ! grep -q "test-e2e.sh" "$path"; then
    fail "$label: missing 'test-e2e.sh' reference ($path)"
  fi

  if ! grep -qi "no additional ask\|no ask\|not ask\|do not ask" "$path"; then
    fail "$label: missing no-ask phrasing ($path)"
  fi
}

check_file "$REPO_ROOT/skills/aidex-conventions/references/worktree-conventions.md" \
  "worktree-conventions.md"

check_file "$REPO_ROOT/skills/aidex-worktree/references/03-case-taxonomy.md" \
  "03-case-taxonomy.md"

check_file "$REPO_ROOT/skills/aidex-worktree/assets/templates/worktree-overview.md.template" \
  "worktree-overview.md.template"

check_file "$HOME/.aidex/rules/e2e-testing.md" \
  "~/.aidex/rules/e2e-testing.md"

if [ "$failures" -eq 0 ]; then
  echo "OK"
  exit 0
else
  echo "$failures failure(s)"
  exit 1
fi
