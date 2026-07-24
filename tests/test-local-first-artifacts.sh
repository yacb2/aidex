#!/usr/bin/env bash
# test-local-first-artifacts.sh — verifies the local-first artifact flow
# contract: the global rule exists and carries all 4 numbered behaviors,
# install.sh ships rules/*.md generically, and dash-conventions carries the
# sibling-report GENERATED clause.
#
# Run with: bash tests/test-local-first-artifacts.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

RULE_FILE="$REPO_ROOT/rules/artifacts-local-first.md"

# Drift repair 2026-07-24: two assertions here grepped for prose wording that
# abc28cd removed from the rule while keeping both behaviors, so the guards went
# dead one day after they were written. Assertions that must survive a rewrite of
# the rule's prose now anchor on a MECHANISM (a script path, a skill name) rather
# than a sentence, and prose checks run against a whitespace-flattened copy so a
# re-wrap cannot split a phrase across lines and silently fail the match.
RULE_FLAT=""
[ -f "$RULE_FILE" ] && RULE_FLAT="$(tr '\n' ' ' < "$RULE_FILE" | tr -s ' ')"

# --- Task 6.1: global rule exists and carries the 4 numbered behaviors ---
if [ ! -f "$RULE_FILE" ]; then
  fail "rule file not found ($RULE_FILE)"
else
  # behavior 1 — the artifact stands alone offline. Anchored on the script that
  # deterministically enforces it plus the prohibition it checks, not on a phrase.
  if ! grep -q "check-artifact.sh" "$RULE_FILE"; then
    fail "rule missing behavior 1 (self-containment enforced via check-artifact.sh)"
  fi
  if ! grep -qF "no external CSS/JS/fonts/images" "$RULE_FILE"; then
    fail "rule missing behavior 1 (external-asset prohibition)"
  fi
  if ! grep -q "sibling" "$RULE_FILE"; then
    fail "rule missing behavior 2 (sibling placement)"
  fi
  if ! grep -q "open <file>" "$RULE_FILE"; then
    fail "rule missing behavior 3 (open locally)"
  fi
  if ! grep -qi "publish online.*only" "$RULE_FILE"; then
    fail "rule missing behavior 4 (publish gated on explicit ask)"
  fi
  if ! grep -q "<slug>-report.html" "$RULE_FILE"; then
    fail "rule missing sibling naming convention (<slug>-report.html)"
  fi
  if ! grep -qi "D-04" "$RULE_FILE"; then
    fail "rule missing English-content (D-04) clause"
  fi
  # Regression (field, 2026-07-23): an ad-hoc "HTML offline" ask was hand-rolled
  # without design guidance after aidex-dash declined — loading artifact-design
  # must be an explicit numbered step, and dash must route instead of just decline.
  # The design-guidance step must be named AND ordered before markup is written.
  # Two anchors: the skill name (a mechanism) and the ordering constraint, matched
  # against the flattened copy so the rule's line wrapping is irrelevant.
  if ! grep -q "artifact-design" "$RULE_FILE"; then
    fail "rule does not name the artifact-design skill"
  fi
  if ! printf '%s' "$RULE_FLAT" | grep -qiE 'before writing any page markup|load design guidance first'; then
    fail "rule missing mandatory load-design-guidance-BEFORE-markup ordering"
  fi
  if ! grep -qi "hand-roll" "$RULE_FILE"; then
    fail "rule missing no-hand-rolled-page clause"
  fi
  # Single-artifact-interface doctrine (ADR 2026-07-23): the rule routes
  # board-shaped asks to dash's renderer, carries the anchor-less fallback,
  # and applies the per-project style profile.
  if ! grep -q "render.sh" "$RULE_FILE"; then
    fail "rule missing board routing to dash render.sh"
  fi
  if ! grep -q ".context/reports/" "$RULE_FILE"; then
    fail "rule missing anchor-less fallback (.context/reports/)"
  fi
  if ! grep -q "artifact-style.md" "$RULE_FILE"; then
    fail "rule missing project style-profile step"
  fi
fi

if [ ! -f "$REPO_ROOT/skills/aidex-dash/assets/templates/artifact-style.md.template" ]; then
  fail "artifact-style.md.template missing in aidex-dash assets"
fi
if ! grep -q "user-invocable-only" "$REPO_ROOT/skills/aidex-dash/SKILL.md"; then
  fail "aidex-dash SKILL.md missing the user-invocable-only scope note"
fi

if ! grep -qi "artifact-design" "$REPO_ROOT/skills/aidex-dash/SKILL.md"; then
  fail "aidex-dash SKILL.md does not route declined ad-hoc asks to artifact-design"
fi

# --- Task 6.1: install.sh covers rules/*.md generically ---
if ! grep -q 'rules/\*\.md' "$REPO_ROOT/install.sh"; then
  fail "install.sh does not glob rules/*.md"
fi
# Regression (field, 2026-07-23): rules copied to ~/.aidex/rules never load —
# Claude Code only reads ~/.claude/rules/*.md, so install must symlink them.
if grep -qE 'rules/\*\)\s*return 1' "$REPO_ROOT/install.sh"; then
  fail "install.sh still excludes rules/* from symlinking (rules would never load)"
fi

# --- Task 6.2: dash-conventions carries the sibling-report GENERATED clause ---
DASH_CONV="$REPO_ROOT/skills/aidex-dash/references/01-dash-conventions.md"
if [ ! -f "$DASH_CONV" ]; then
  fail "dash-conventions.md not found ($DASH_CONV)"
else
  if ! grep -q "sibling report" "$DASH_CONV"; then
    fail "dash-conventions.md missing sibling-report clause"
  fi
  if ! grep -q "artifacts-local-first.md" "$DASH_CONV"; then
    fail "dash-conventions.md does not reference rules/artifacts-local-first.md"
  fi
fi

DASH_SKILL="$REPO_ROOT/skills/aidex-dash/SKILL.md"
if [ ! -f "$DASH_SKILL" ]; then
  fail "aidex-dash SKILL.md not found ($DASH_SKILL)"
else
  if ! grep -q "artifacts-local-first.md" "$DASH_SKILL"; then
    fail "aidex-dash SKILL.md does not mention rules/artifacts-local-first.md"
  fi
fi

if [ "$failures" -eq 0 ]; then
  echo "OK"
  exit 0
else
  echo "$failures failure(s)"
  exit 1
fi
