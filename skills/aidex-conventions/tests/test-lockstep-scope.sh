#!/usr/bin/env bash
# Ownership scope of test_registry_lockstep.py (regression for BL-115).
#
# Installed, SKILLS_DIR resolves to ~/.aidex/skills, which holds the user's own
# skills alongside aidex's 17. The guard enumerated everything under that root
# and FAILed on five `doc-standards` agents and one `workspace-architecture`
# description — files this repo does not ship and has no standing to judge. The
# repo copy passed at the same time, because there the root is aidex-only, so
# suite health looked green while every installed user saw FAIL on a clean tree.
#
# Invariants:
#   1. A foreign skill under the scan root does not change the verdict.
#   2. Scoping did not weaken the rule: an aidex-owned violation still FAILs.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GUARD_REL="skills/aidex-conventions/scripts/test_registry_lockstep.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

# A fake install root. Copies, not symlinks: the guard resolves __file__, so a
# symlinked skill would walk straight back into the repo and prove nothing.
cp -R "$REPO/skills" "$TMP/skills"
cp -R "$REPO/rules" "$TMP/rules"
cp -R "$REPO/hooks" "$TMP/hooks"

# What install.sh writes — the authoritative aidex-owned inventory.
: > "$TMP/.manifest"
for d in "$TMP"/skills/*/; do echo "skills/$(basename "$d")" >> "$TMP/.manifest"; done

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

if [ "$fail" -eq 0 ]; then
  echo "OK: registry lockstep judges only aidex-owned skills (foreign skill ignored, own violation still caught)"
fi
exit "$fail"
