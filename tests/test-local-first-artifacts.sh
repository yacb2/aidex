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

# Relocation 2026-08-05 (RA-ART-1): a rule-ablation audit measured this rule at 3.3%
# of field sessions for 655 always-on words — the highest waste in the set. The
# procedure moved to an on-demand canon and the always-on rule kept only what cannot
# be recovered later: the request-shape ROUTING and the two GATES.
#
# So the contract is now a PAIR, and this test asserts the split rather than the old
# monolith: gates stay resident, procedure lives in the canon, and — the failure mode
# relocation introduces — the rule's pointer must resolve to a file that exists.
# A dangling pointer is silent: the stub still says "read this", and nothing errors.
CANON_FILE="$REPO_ROOT/skills/aidex-dash/references/02-local-first-artifacts.md"
# Same for the canon. Any assertion on a MULTI-WORD phrase must read the flattened
# copy: markdown rewraps, and a line-based grep then reports a missing rule that is
# right there. That false negative fired twice on 2026-08-06 (here and in
# test_publish_policy_lockstep.sh). Single-token greps cannot straddle a newline and
# are left alone.
[ -f "$CANON_FILE" ] && CANON_FLAT="$(tr '\n' ' ' < "$CANON_FILE" | tr -s ' ')"

# --- Task 6.1a: the always-on rule keeps routing + both gates + the pointer ---
if [ ! -f "$RULE_FILE" ]; then
  fail "rule file not found ($RULE_FILE)"
else
  if ! grep -qi "publish.*only\|never publish" <<<"$RULE_FLAT"; then
    fail "rule missing gate 2 (publish gated on explicit ask) — must stay always-on"
  fi
  if ! grep -qi "D-04" "$RULE_FILE"; then
    fail "rule missing English-content (D-04) clause"
  fi
  # The pointer must be present AND resolve. Anchored on the basename so the rule
  # may write it as an absolute ~/.aidex path or a repo-relative one.
  if ! grep -q "02-local-first-artifacts.md" "$RULE_FILE"; then
    fail "rule does not point at the on-demand canon (02-local-first-artifacts.md)"
  fi
  if [ ! -f "$CANON_FILE" ]; then
    fail "rule's pointer dangles — $CANON_FILE does not exist"
  fi
fi

# --- Task 6.1b: the on-demand canon carries the procedure ---
if [ ! -f "$CANON_FILE" ]; then
  fail "on-demand canon not found ($CANON_FILE)"
else
  # behavior 1 — the artifact stands alone offline. Anchored on the script that
  # deterministically enforces it plus the prohibition it checks, not on a phrase.
  if ! grep -q "check-artifact.sh" "$CANON_FILE"; then
    fail "canon missing behavior 1 (self-containment enforced via check-artifact.sh)"
  fi
  if ! grep -qF "no external CSS/JS/fonts/images" <<<"$CANON_FLAT"; then
    fail "canon missing behavior 1 (external-asset prohibition)"
  fi
  if ! grep -q "sibling" "$CANON_FILE"; then
    fail "canon missing behavior 2 (sibling placement)"
  fi
  if ! grep -q "open <file>" <<<"$CANON_FLAT"; then
    fail "canon missing behavior 3 (open locally)"
  fi
  if ! grep -q "<slug>-report.html" "$CANON_FILE"; then
    fail "canon missing sibling naming convention (<slug>-report.html)"
  fi
  if ! grep -q "wrap-report.sh" "$CANON_FILE"; then
    fail "canon missing the document-envelope step (wrap-report.sh)"
  fi
fi

if [ -f "$RULE_FILE" ]; then
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
  # Single-artifact-interface doctrine (ADR 2026-07-23): routing board-shaped asks
  # to dash's renderer is the ROUTE decision, so it stays in the always-on rule.
  if ! grep -q "render.sh" "$RULE_FILE"; then
    fail "rule missing board routing to dash render.sh"
  fi
fi

# The anchor-less fallback and the per-project style profile are procedure, so they
# moved with it (RA-ART-1). They are still mandatory — only their home changed.
if [ -f "$CANON_FILE" ]; then
  if ! grep -q ".context/reports/" "$CANON_FILE"; then
    fail "canon missing anchor-less fallback (.context/reports/)"
  fi
  if ! grep -q "artifact-style.md" "$CANON_FILE"; then
    fail "canon missing project style-profile step"
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
