#!/usr/bin/env bash
# run-all.sh — run every test in the repo, wherever it lives.
#
# Why this exists: the suite is spread over several locations — `tests/test-*.sh`,
# `skills/*/tests/test-*.sh`, and `skills/*/scripts/test[-_]*.{sh,py}`. Sweeps that walked
# the first two silently skipped the third, and on 2026-08-06 an over-maximum SKILL.md body
# reached a commit with the suite reported green because `test_skill_budget.sh` sits in
# `scripts/` (BL-113). A runner that discovers tests cannot develop that blind spot.
#
# It developed one anyway. The `scripts/` globs matched `test_*` only, so every
# HYPHENATED test under `skills/*/scripts/` was invisible — 17 of them, including
# `test-find-project-root.sh`, whose whole job is to fail when a script defines a
# private `find_project_root`. That guard was unwired the day it was written, and
# the runner still reported green. Naming style is not a reason to skip a test.
#
# The pattern is now guarded rather than re-patched: tests/test-discovery-census.sh
# enumerates test files by NAME across the tree and asserts each is either in
# `--list` or excluded by name with a reason. A test in a new location fails it
# once, and the fix is a glob here, not a line in that exclusion list.
#
# And a third time, 2026-08-17: `hooks/` was never a discovery root, so both hook
# tests were invisible. `test-context-depth-nudge.py` had been asserting that the
# depth hook TELLS the assistant not to hand off on its own — pinning a rule the
# hook does not own and that `skills/conventions/references/autonomy-conventions.md` answers the other way inside a
# run. A test nobody runs is how a checker that certifies the defect survives.
# Location is not a reason to skip a test either.
#
# Docker-dependent tests are opted into, not discovered: nine worktree
# tests need a live daemon and take minutes, and folding them in by default would
# turn a seconds-long daemon-free suite into one that cannot run on a laptop with
# Docker closed. `RUN_DOCKER_TESTS=1 tests/run-all.sh` includes them.
#
# ONE ROOT IS NOT ENOUGH. Every test above runs from the checkout, where skills/
# holds aidex and nothing else. Installed, the same file runs from ~/.claude/skills,
# which also holds the user's own skills and carries a manifest. Three tests were
# green here and red there at the same moment — test_skill_budget.sh FAILing on a
# user skill, test_workflow_core_drift.sh latently the same, and a coverage gate
# resolving .context/ against ~/.claude. That is BL-115's shape, and a runner with
# one root cannot see it: the second root is where users live.
#
# The invariant is SAME VERDICT IN BOTH, not green in both. A test red in both
# roots is one repo failure, already reported above; only a divergence is a parity
# failure.
#
# Cost decides the default. The full shipped subset is 114 tests / ~406s against a
# ~431s suite — 94% more for a property most tests cannot violate. A test under
# skills/<x>/{tests,scripts}/ can only observe the root by climbing to it, and the
# climb is syntactic: `../..`, $HOME/.claude, aidex/manifest, or pathlib's
# parents[2+]. A `../../<name>` hop reaches a SIBLING SKILL, which every
# install has, so it is root-independent and does not count. That selector picks
# 21 tests / ~16s (+3.8%), and picks all three of the defects above — 3/3,
# measured 2026-09-07, not asserted. `RUN_INSTALL_PARITY=full` re-runs the whole
# shipped subset instead.
#
# There is no CI in this repo, so the parity pass runs when someone runs the
# suite. `full` is intent, not a gate.
#
# Usage:
#   tests/run-all.sh            # quiet: one line per test, failures reprinted in full
#   tests/run-all.sh --verbose  # stream every test's output as it runs
#
# Exit 0 only when every test passes and no test changes verdict between roots.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"

VERBOSE=0
LIST_ONLY=0
case "${1:-}" in
  --verbose|-v) VERBOSE=1 ;;
  # `--list` prints the discovered set and exits. It exists so the discovery
  # census (tests/test-discovery-census.sh) can ask this file what it found
  # instead of re-implementing the globs — a second copy of them would drift,
  # which is the defect the census is there to catch.
  --list)       LIST_ONLY=1 ;;
esac

shopt -s nullglob
TESTS=(tests/test-*.sh skills/*/tests/test-*.sh
       skills/*/scripts/test_*.sh skills/*/scripts/test_*.py
       skills/*/scripts/test-*.sh skills/*/scripts/test-*.py
       hooks/test-*.sh hooks/test-*.py)
# worktree's scripts/test-*.sh are the docker set; the branch below owns
# them and names the one liar among them. Drop them from the general glob rather
# than letting both paths claim them.
_KEPT=()
for _t in "${TESTS[@]}"; do
  [[ "$_t" == skills/worktree/scripts/test-* ]] || _KEPT+=("$_t")
done
TESTS=("${_KEPT[@]}")
if [[ "${RUN_DOCKER_TESTS:-0}" == "1" ]]; then
  # `test-db-preflight.sh` is a PRODUCTION script, not a test: it preflights the
  # TEST database, which is why its name starts that way. Discovery by filename
  # cannot tell the two apart, so the one liar is named here. Its real test is
  # `test-test-db-preflight.sh`, which the glob picks up.
  for _wt in skills/worktree/scripts/test-*.sh; do
    [[ "$_wt" == */test-db-preflight.sh ]] && continue
    TESTS+=("$_wt")
  done
else
  DOCKER_SKIPPED=(skills/worktree/scripts/test-*.sh)
fi
DOCKER_SKIPPED=("${DOCKER_SKIPPED[@]:-}")
[[ -z "${DOCKER_SKIPPED[0]:-}" ]] && DOCKER_SKIPPED=()
shopt -u nullglob

if [[ $LIST_ONLY -eq 1 ]]; then
  printf '%s\n' "${TESTS[@]}"
  exit 0
fi

PASS=0
SKIPPED=0
SKIP_REASONS=()
FAILED=()
# Parity findings are tracked apart from FAILED: they are not members of $TESTS (or are
# already counted in PASS), so folding them in breaks the tally's arithmetic.
PARITY_ISSUES=()
LOG="$(mktemp)"
VERDICTS="$(mktemp)"          # "<rc> <path>" per test, for the parity pass
PARITY_HOME="$(mktemp -d)"
trap 'rm -f "$LOG" "$VERDICTS"; rm -rf "$PARITY_HOME"' EXIT

for t in "${TESTS[@]}"; do
  # Python tests import sibling modules by relative name, so run them from their own dir.
  case "$t" in
    *.py) ( cd "$(dirname "$t")" && python3 "$(basename "$t")" ) >"$LOG" 2>&1 ;;
    *)    bash "$t" >"$LOG" 2>&1 ;;
  esac
  rc=$?
  printf '%d %s\n' "$rc" "$t" >> "$VERDICTS"
  # Exit 2 is this repo's SKIP (docker absent, a singleton lock already held).
  # A skipped test is not a failed one, and it must not be silently counted as a
  # pass either — it is printed as what it is.
  if [[ $rc -eq 2 ]] && grep -q '^SKIP' "$LOG"; then
    printf 'SKIP  %s\n' "$t"
    SKIPPED=$((SKIPPED + 1))
    SKIP_REASONS+=("$t — $(grep -m1 '^SKIP' "$LOG")")
    [[ $VERBOSE -eq 1 ]] && cat "$LOG"
    continue
  fi
  if [[ $rc -eq 0 ]]; then
    PASS=$((PASS + 1))
    printf 'PASS  %s\n' "$t"
    [[ $VERBOSE -eq 1 ]] && cat "$LOG"
  else
    FAILED+=("$t")
    printf 'FAIL  %s (exit %d)\n' "$t" "$rc"
    cat "$LOG"
  fi
done

printf '\n'
# A skipped test is announced, never silent: "65/65 passed" over a set that
# quietly excluded a whole family is exactly the claim this runner exists to
# stop making. The tally is printed at the very END instead of here, because
# the parity pass below can still add failures and a "0 failed" line standing
# above a `failed:` line is worse than no line at all.
if [[ ${#DOCKER_SKIPPED[@]} -gt 0 ]]; then
  printf 'skipped %d docker-dependent test(s) — run with RUN_DOCKER_TESTS=1 to include them\n' \
    "${#DOCKER_SKIPPED[@]}"
fi

# ---------------------------------------------------------------------------
# Second root — the same shipped tests, from an install-shaped tree.
# Same verdict in both is the invariant; see the header for why and what it costs.
# ---------------------------------------------------------------------------

# Shipped = what the plugin carries under skills/. tests/ and hooks/test-* never reach
# a user, so they have no second root to differ in. Docker tests are excluded even under
# RUN_DOCKER_TESTS=1: they create containers, and doing that twice per suite to
# re-check a path-resolution property is not a trade worth making.
PARITY_POOL=()
for t in "${TESTS[@]}"; do
  case "$t" in
    tests/*|hooks/*|skills/worktree/scripts/test-*) continue ;;
  esac
  PARITY_POOL+=("$t")
done

# A test under skills/<x>/{tests,scripts}/ can only observe the root by climbing to
# it, and every climb is one of these four syntactic forms. `../../<name>`
# is a hop to a SIBLING SKILL — present in every install — so it is root-independent
# and deliberately not a match; without that exclusion the set is 32 tests / ~91s
# instead of 21 / ~16s, for no added coverage.
ROOT_REACHING='\.\./\.\.|\$HOME/\.claude|aidex/manifest|parents\[[2-9]\]|\.parent\.parent\.parent'
PARITY=()
if [[ "${RUN_INSTALL_PARITY:-}" == "full" ]]; then
  PARITY=("${PARITY_POOL[@]}")
else
  # NOT `grep -v ... | grep -q ...`. Under `set -o pipefail` that pipeline is a
  # race: `grep -q` exits at the FIRST match and closes the pipe, `grep -v` takes
  # SIGPIPE if it is still writing, and pipefail then reports 141 for a file that
  # DID match. It only bites when the file exceeds the pipe buffer, so it looked
  # like a stable 21 and was intermittently 20 — measured 2026-09-07 at 1 miss in
  # 840 evaluations under load, always on the largest file in the pool
  # (test_registry_lockstep.py, 38 KB). Silent, load-dependent under-selection is
  # the worst failure this pass could have: it drops a test from the check and
  # still prints a green line.
  for t in "${PARITY_POOL[@]}"; do
    filtered="$(grep -v -E '\.\./\.\./(artifact|audit|backlog|bugfix|comm|conventions|coverage|decision|loop|plan-exec|plan|reference|request|research|review|skill|workflow|worktree)/' "$t" 2>/dev/null)"
    if [[ $? -gt 1 ]]; then
      printf 'parity: FAIL — could not read %s while selecting\n' "$t"
      PARITY_ISSUES+=("parity:unreadable:$t")
      continue
    fi
    if printf '%s\n' "$filtered" | grep -qE "$ROOT_REACHING"; then
      PARITY+=("$t")
    fi
  done
fi

[[ $VERBOSE -eq 1 ]] && printf 'parity selected: %s\n' "${PARITY[@]}"

# A selector that silently selected nothing would print a green parity line over an
# empty set — the exact "checker lies by omission" shape this runner keeps meeting.
if [[ ${#PARITY[@]} -eq 0 ]]; then
  printf 'parity: FAIL — the root-reaching selector matched 0 of %d shipped tests\n' "${#PARITY_POOL[@]}"
  PARITY_ISSUES+=("parity:selector-matched-nothing")
fi

DIVERGED=()
if [[ ${#PARITY[@]} -gt 0 ]]; then
  # aidex ships as a plugin since v1.0.0, so there is no installer to build this root
  # with (docs/retired/install.sh resolved everything relative to its own directory).
  # The root is the INSTALLED PLUGIN's shape — ~/.claude/plugins/aidex/ — copied from
  # the WORKING TREE, so an uncommitted regression still shows up here. The property
  # under test is unchanged and is the reason this pass exists: a shipped test must
  # resolve the same from a non-checkout root, next to skills aidex does not own.
  #
  # Where the foreign skill goes moved with the migration, and the move is the point.
  # The installer copied aidex INTO ~/.claude/skills, so a user skill landed in the
  # same directory and every unscoped walker judged it (BL-115). A plugin's skills/
  # is aidex-only by construction; a user's own skills sit OUTSIDE it, in
  # ~/.claude/skills/, which is where the fixture plants one.
  if ! { mkdir -p "$PARITY_HOME/.claude/plugins" \
           && cp -R "$REPO_ROOT" "$PARITY_HOME/.claude/plugins/aidex"; } >"$LOG" 2>&1; then
    printf 'parity: FAIL — could not build the install root\n'
    cat "$LOG"
    PARITY_ISSUES+=("parity:install-failed")
  else
    FAKE="$PARITY_HOME/.claude/plugins/aidex"
    # A user's HOME is never aidex-only. This skill, outside the plugin, is the whole
    # difference between the two roots.
    #
    # It VIOLATES aidex's own rules on purpose, and a benign one would make this
    # whole pass vacuous: an unscoped guard only diverges when the foreign skill
    # gives it something to report. These three are the real shapes — a body over
    # the size budget (session-handoff ships at ~6.4k tokens against a 5k maximum),
    # a workflow asset whose blocks are not aidex's, and an agent with no `effort`.
    # None of them is aidex's to judge, which is the entire point.
    FOREIGN="$PARITY_HOME/.claude/skills/foreign-skill"
    mkdir -p "$FOREIGN/assets/workflows" "$FOREIGN/agents"
    {
      printf -- '---\nname: foreign-skill\ndescription: A user skill living beside aidex.\n---\n\n'
      i=0; while [[ $i -lt 600 ]]; do
        echo "Body line long enough that this skill blows the token axis as well as the line axis."
        i=$((i + 1))
      done
    } > "$FOREIGN/SKILL.md"
    printf -- '// === CORE:START ===\nconst notOurs = true\n// === CORE:END ===\n// === ARBITER:START ===\nconst alsoNotOurs = true\n// === ARBITER:END ===\n' \
      > "$FOREIGN/assets/workflows/foreign.workflow.js"
    printf -- '---\nname: foreign-agent\nmodel: sonnet\n---\n\nBody.\n' \
      > "$FOREIGN/agents/foreign-agent.md"

    for t in "${PARITY[@]}"; do
      here="$(awk -v p="$t" '$2 == p {print $1; exit}' "$VERDICTS")"
      [[ -n "$here" ]] || continue
      [[ -f "$FAKE/$t" ]] || { DIVERGED+=("$t (not installed)"); continue; }
      case "$t" in
        *.py) ( cd "$FAKE/$(dirname "$t")" && python3 "$(basename "$t")" ) >"$LOG" 2>&1 ;;
        *)    ( cd "$FAKE" && bash "$t" ) >"$LOG" 2>&1 ;;
      esac
      there=$?
      if [[ "$there" -ne "$here" ]]; then
        DIVERGED+=("$t")
        printf 'PARITY  %s — exit %d from the checkout, exit %d from an installed-plugin root\n' "$t" "$here" "$there"
        cat "$LOG"
      fi
    done
  fi
fi

if [[ ${#PARITY[@]} -gt 0 ]]; then
  printf 'parity: %d of %d shipped tests re-run in an installed-plugin root, %d diverged' \
    "${#PARITY[@]}" "${#PARITY_POOL[@]}" "${#DIVERGED[@]}"
  [[ "${RUN_INSTALL_PARITY:-}" == "full" ]] \
    && printf ' (full)\n' \
    || printf ' (root-reaching only — RUN_INSTALL_PARITY=full for all %d)\n' "${#PARITY_POOL[@]}"
fi
if [[ ${#DIVERGED[@]} -gt 0 ]]; then
  printf 'diverged between roots: %s\n' "${DIVERGED[*]}"
  PARITY_ISSUES+=("${DIVERGED[@]}")
fi

# The tally, in three named categories rather than one ratio. "137/139 passed" reads as
# red whatever the two were, and inside a worktree the two were STRUCTURAL — a
# precondition that checkout cannot have, not a regression (BL-338). A run is citable as
# green on `0 failed` plus exit 0; the skipped ones are listed with the reason each
# printed, so "skipped" can never quietly mean "did not look".
#
# The three categories PARTITION $TESTS, which is why parity findings are not in them: a
# test that passes here and diverges in the install root is already counted in `passed`,
# and `parity:install-failed` is not a member of $TESTS at all. Folding either into
# `failed` made the line report 142 outcomes over 141 tests — self-contradictory in
# exactly the red runs a reader reads it in. They get their own line, and they still
# decide the exit code.
printf '\n%d tests: %d passed, %d skipped, %d failed\n' \
  "${#TESTS[@]}" "$PASS" "$SKIPPED" "${#FAILED[@]}"
if [[ $SKIPPED -gt 0 ]]; then
  printf 'the %d skip(s) are structural — a precondition this environment lacks, not a failure:\n' "$SKIPPED"
  printf '  %s\n' "${SKIP_REASONS[@]}"
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
  printf 'failed: %s\n' "${FAILED[*]}"
fi
if [[ ${#PARITY_ISSUES[@]} -gt 0 ]]; then
  printf 'parity findings (outside the tally above — the tally counts the checkout run): %s\n' \
    "${PARITY_ISSUES[*]}"
fi
if [[ ${#FAILED[@]} -gt 0 || ${#PARITY_ISSUES[@]} -gt 0 ]]; then
  exit 1
fi
