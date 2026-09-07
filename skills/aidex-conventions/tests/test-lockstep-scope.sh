#!/usr/bin/env bash
# Ownership scope of every guard that walks the skills root (regression for BL-115).
#
# Installed, the skills root resolves to ~/.claude/skills, which holds the user's
# own skills alongside aidex's. test_registry_lockstep.py enumerated everything
# under that root and FAILed on five `doc-standards` agents and one
# `workspace-architecture` description — files this repo does not ship and has no
# standing to judge. The repo copy passed at the same time, because there the root
# is aidex-only, so suite health looked green while every installed user saw FAIL
# on a clean tree.
#
# Scoping the registry guard fixed one walker and left two. Measured 2026-09-07 on
# the real install: test_skill_budget.sh FAILs on `session-handoff`, a user skill
# at ~6.4k tokens — same defect, still live. test_workflow_core_drift.sh is the
# same class and passes only because no installed skill happens to ship a
# `assets/workflows/*.workflow.js`; the first one that does gets judged against
# aidex's canonical CORE block.
#
# Invariants, asserted for each guard:
#   1. A foreign skill under the scan root does not change the verdict.
#   2. Scoping did not weaken the rule: an aidex-owned violation still FAILs.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GUARD_REL="skills/aidex-conventions/scripts/test_registry_lockstep.py"
BUDGET_REL="skills/aidex-conventions/scripts/test_skill_budget.sh"
DRIFT_REL="skills/aidex-conventions/scripts/test_workflow_core_drift.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

# A fake install root. Copies, not symlinks: the guard resolves __file__, so a
# symlinked skill would walk straight back into the repo and prove nothing.
cp -R "$REPO/skills" "$TMP/skills"
cp -R "$REPO/rules" "$TMP/rules"
cp -R "$REPO/hooks" "$TMP/hooks"

# What install.sh writes — the authoritative aidex-owned inventory, at the path
# install.sh actually writes it to (`$STATE_DIR/manifest`, i.e. <root>/aidex/manifest).
# Writing it at <root>/.manifest instead is what let the guard fall back to
# scanning every skill on a real install while this test stayed green: the test
# was pinning the path the code read, not the path the installer wrote.
# Only the aidex namespace, which is what install.sh records. Listing every
# directory the copy produced is the same thing in the repo (the tree is
# aidex-only) and wrong from an installed root, where $REPO is ~/.claude and the
# copy also carries the user's own skills: the fixture would declare them
# aidex-owned and the guard would report them, correctly, as out-of-namespace.
mkdir -p "$TMP/aidex"
: > "$TMP/aidex/manifest"
for d in "$TMP"/skills/aidex*/; do
  [ -d "$d" ] || continue
  echo "skills/$(basename "$d")" >> "$TMP/aidex/manifest"
done

long_desc="$(printf 'x%.0s' $(seq 950))"

# ---- 1. a foreign skill is out of scope -----------------------------------
# Two violations the guard is right about in kind and wrong to report here: an
# agent with no `effort`, and a description over the 900-char budget.
mkdir -p "$TMP/skills/foreign-skill/agents"
printf -- '---\nname: foreign-skill\ndescription: %s\n---\n\nBody.\n' \
  "$long_desc" > "$TMP/skills/foreign-skill/SKILL.md"
printf -- '---\nname: foreign-agent\nmodel: sonnet\n---\n\nBody.\n' \
  > "$TMP/skills/foreign-skill/agents/foreign-agent.md"

out="$(python3 "$TMP/$GUARD_REL" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -ne 0 ]; then
  err "a foreign skill under the scan root flipped the verdict to FAIL:"
  echo "$out" | sed 's/^/       /' >&2
elif echo "$out" | grep -q 'foreign-skill'; then
  err "verdict is OK but the report still names foreign-skill"
fi

# ---- 2. the rule still bites on aidex's own files -------------------------
# Same defect, this time in a skill the manifest claims. Scoping the guard must
# not turn it into a check that cannot fail.
mkdir -p "$TMP/skills/aidex-plan/agents"
printf -- '---\nname: probe-agent\nmodel: sonnet\n---\n\nBody.\n' \
  > "$TMP/skills/aidex-plan/agents/probe-agent.md"

out="$(python3 "$TMP/$GUARD_REL" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 0 ]; then
  err "an aidex-owned agent with no effort did not FAIL — the guard was neutered"
elif ! echo "$out" | grep -q 'probe-agent'; then
  err "FAILed, but not on probe-agent — check the reason:"
  echo "$out" | sed 's/^/       /' >&2
fi

# ---- 3. the size budget is out of scope for a foreign skill ---------------
# A user skill over the 500-line / 5000-token maximum is not aidex's to fail.
# This is not hypothetical: on the real install `session-handoff` sits at ~6.4k
# tokens and the installed guard FAILs on it.
mkdir -p "$TMP/skills/foreign-skill"
{
  printf -- '---\nname: foreign-skill\ndescription: A user skill, oversized on purpose.\n---\n\n'
  for _ in $(seq 600); do echo "Body line that is deliberately long enough to also blow the token axis."; done
} > "$TMP/skills/foreign-skill/SKILL.md"

out="$(bash "$TMP/$BUDGET_REL" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -ne 0 ]; then
  err "an oversized foreign SKILL.md flipped the budget guard to FAIL:"
  echo "$out" | sed 's/^/       /' >&2
elif echo "$out" | grep -q 'foreign-skill'; then
  err "budget verdict is OK but the report still names foreign-skill"
fi

# ---- 4. the size budget still bites on aidex's own files ------------------
{
  printf -- '\n'
  for _ in $(seq 600); do echo "Body line that is deliberately long enough to also blow the token axis."; done
} >> "$TMP/skills/aidex-decision/SKILL.md"

out="$(bash "$TMP/$BUDGET_REL" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 0 ]; then
  err "an oversized aidex-owned SKILL.md did not FAIL — the budget guard was neutered"
elif ! echo "$out" | grep -q 'aidex-decision'; then
  err "budget FAILed, but not on aidex-decision — check the reason:"
  echo "$out" | sed 's/^/       /' >&2
fi

# ---- 5. the workflow drift-lock is out of scope for a foreign asset -------
# No installed skill ships one today, which is the only reason this guard is
# not already red for every user. A drifted CORE block in someone else's
# workflow asset is not aidex's finding.
mkdir -p "$TMP/skills/foreign-skill/assets/workflows"
printf -- '// === CORE:START ===\nconst notOurs = true\n// === CORE:END ===\n// === ARBITER:START ===\nconst alsoNotOurs = true\n// === ARBITER:END ===\n' \
  > "$TMP/skills/foreign-skill/assets/workflows/foreign.workflow.js"

out="$(bash "$TMP/$DRIFT_REL" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -ne 0 ]; then
  err "a foreign workflow asset flipped the drift-lock to FAIL:"
  echo "$out" | sed 's/^/       /' >&2
elif echo "$out" | grep -q 'foreign-skill'; then
  err "drift verdict is OK but the report still names foreign-skill"
fi

# ---- 6. the drift-lock still bites on aidex's own assets -----------------
mkdir -p "$TMP/skills/aidex-decision/assets/workflows"
printf -- '// === CORE:START ===\nconst drifted = true\n// === CORE:END ===\n// === ARBITER:START ===\nconst alsoDrifted = true\n// === ARBITER:END ===\n' \
  > "$TMP/skills/aidex-decision/assets/workflows/probe.workflow.js"

out="$(bash "$TMP/$DRIFT_REL" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 0 ]; then
  err "a drifted aidex-owned workflow asset did not FAIL — the drift-lock was neutered"
elif ! echo "$out" | grep -q 'aidex-decision'; then
  err "drift FAILed, but not on aidex-decision — check the reason:"
  echo "$out" | sed 's/^/       /' >&2
fi

if [ "$fail" -eq 0 ]; then
  echo "OK: the three skills-root guards judge only aidex-owned skills (foreign skill ignored, own violation still caught in each)"
fi
exit "$fail"
