#!/usr/bin/env bash
# The three guards that walk the skills tree still bite on a violation in aidex's own files.
#
# Reduced from the BL-115 ownership test: the manifest filtering is gone (the checkout is
# aidex-only by construction, _owned-skills.sh), but the guards' bite-proof stays — a guard
# that cannot fail guards nothing. Each case plants one violation in a copied tree and asserts
# the guard exits non-zero AND names the planted file.
#   1. registry guard: agents/probe-agent.md declares no effort
#   2. budget guard: skills/decision/SKILL.md grown by 600 long lines
#   3. drift guard: a drifted CORE/ARBITER block in skills/decision/assets/workflows/
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GUARD_REL="skills/conventions/scripts/test_registry_lockstep.py"
BUDGET_REL="skills/conventions/scripts/test_skill_budget.sh"
DRIFT_REL="skills/conventions/scripts/test_workflow_core_drift.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

# Copies, not symlinks: the guards resolve __file__, so a symlinked skill would walk
# straight back into the repo and prove nothing.
cp -R "$REPO/skills" "$TMP/skills"
cp -R "$REPO/hooks" "$TMP/hooks"
cp -R "$REPO/agents" "$TMP/agents"   # plugin-level agent definitions (guard 7 walks them)

# Baseline: every guard is green on the untouched copy, so a later FAIL is the planted one.
for g in "$GUARD_REL" "$BUDGET_REL" "$DRIFT_REL"; do
  case "$g" in *.py) python3 "$TMP/$g" >/dev/null 2>&1 ;; *) bash "$TMP/$g" >/dev/null 2>&1 ;; esac \
    || err "baseline: ${g##*/} fails on an untouched copy"
done

printf -- '---\nname: probe-agent\nmodel: sonnet\n---\n\nBody.\n' > "$TMP/agents/probe-agent.md"
out="$(python3 "$TMP/$GUARD_REL" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 0 ]; then
  err "an aidex-owned agent with no effort did not FAIL — the registry guard was neutered"
elif ! echo "$out" | grep >/dev/null 'probe-agent'; then
  err "registry guard FAILed, but not on probe-agent:"; echo "$out" | sed 's/^/       /' >&2
fi

{
  printf -- '\n'
  for _ in $(seq 600); do echo "Body line that is deliberately long enough to also blow the token axis."; done
} >> "$TMP/skills/decision/SKILL.md"
out="$(bash "$TMP/$BUDGET_REL" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 0 ]; then
  err "an oversized aidex-owned SKILL.md did not FAIL — the budget guard was neutered"
elif ! echo "$out" | grep >/dev/null 'decision'; then
  err "budget guard FAILed, but not on decision:"; echo "$out" | sed 's/^/       /' >&2
fi

mkdir -p "$TMP/skills/decision/assets/workflows"
printf -- '// === CORE:START ===\nconst drifted = true\n// === CORE:END ===\n// === ARBITER:START ===\nconst alsoDrifted = true\n// === ARBITER:END ===\n' \
  > "$TMP/skills/decision/assets/workflows/probe.workflow.js"
out="$(bash "$TMP/$DRIFT_REL" 2>&1)" && rc=0 || rc=$?
if [ "$rc" -eq 0 ]; then
  err "a drifted aidex-owned workflow asset did not FAIL — the drift-lock was neutered"
elif ! echo "$out" | grep >/dev/null 'decision'; then
  err "drift guard FAILed, but not on decision:"; echo "$out" | sed 's/^/       /' >&2
fi

if [ "$fail" -eq 0 ]; then
  echo "OK: the registry, budget and drift guards each still FAIL on a planted violation and name it"
fi
exit "$fail"
