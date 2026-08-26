#!/usr/bin/env bash
# test-close-guard.sh — cells for close-plan.sh's consistency guard (ADR
# 2026-07-19-plan-spec-first): closing as done with unchecked checkboxes is
# blocked (unless --force / --status dropped), and the Session Checkpoint's
# **Status:** line is synced to the front-matter status on close.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/close-plan.sh"
FAILS=0
fail() { echo "FAIL: $*" >&2; FAILS=$((FAILS+1)); }

make_project() {  # fresh temp project with .context/plans
  local td; td="$(mktemp -d)"
  mkdir -p "$td/.context/plans"
  printf '%s\n' "$td"
}

write_plan() {  # $1=path $2=checkbox state ("[ ]" or "[x]")
  cat > "$1" << EOF
---
title: "Guard test plan"
status: doing
created: 2026-07-19
updated: 2026-07-19
---

# Guard Test Plan

## Phase 1 Checkpoint

**Completed:**
- $2 Task 1.1: the work

## Session Checkpoint

**Status:** doing
EOF
}

# 1. done + unchecked box -> blocked, plan stays in place
TD="$(make_project)"; PLAN="$TD/.context/plans/2026-07-19-guard.md"
write_plan "$PLAN" "[ ]"
if (cd "$TD" && bash "$SCRIPT" 2026-07-19-guard >/dev/null 2>&1); then
  fail "close done with unchecked checkbox succeeded (guard did not fire)"
fi
[[ -f "$PLAN" ]] || fail "blocked close still moved the plan"

# 2. done + unchecked + --force -> archived
if ! (cd "$TD" && bash "$SCRIPT" 2026-07-19-guard --force >/dev/null 2>&1); then
  fail "--force did not bypass the guard"
fi
[[ -f "$TD/.context/plans/_archive/2026-07-19-guard.md" ]] || fail "--force close did not archive"
rm -rf "$TD"

# 3. dropped + unchecked -> allowed (dropping unfinished work is the point)
TD="$(make_project)"; write_plan "$TD/.context/plans/2026-07-19-guard.md" "[ ]"
if ! (cd "$TD" && bash "$SCRIPT" 2026-07-19-guard --status dropped >/dev/null 2>&1); then
  fail "close --status dropped was blocked by the checkbox guard"
fi
rm -rf "$TD"

# 4. done + all checked -> archived, front-matter AND **Status:** line both done
TD="$(make_project)"; write_plan "$TD/.context/plans/2026-07-19-guard.md" "[x]"
if ! (cd "$TD" && bash "$SCRIPT" 2026-07-19-guard >/dev/null 2>&1); then
  fail "clean close was blocked"
else
  ARCHIVED="$TD/.context/plans/_archive/2026-07-19-guard.md"
  grep -q '^status: done' "$ARCHIVED" || fail "front-matter status not set to done"
  grep -q '^\*\*Status:\*\* done' "$ARCHIVED" || fail "Session Checkpoint **Status:** not synced to done"
  grep -q '^\*\*Status:\*\* doing' "$ARCHIVED" && fail "stale **Status:** doing survived the close"
fi
rm -rf "$TD"

# 5. modular plan: unchecked box in a phase file blocks the close
TD="$(make_project)"; DIR="$TD/.context/plans/2026-07-19-modular"
mkdir -p "$DIR"
write_plan "$DIR/00-index.md" "[x]"
printf '# Phase 1: Slice\n\n- [ ] Task 1.1: pending\n' > "$DIR/01-slice.md"
if (cd "$TD" && bash "$SCRIPT" 2026-07-19-modular >/dev/null 2>&1); then
  fail "modular close done with unchecked phase-file checkbox succeeded"
fi
rm -rf "$TD"

# 6. regression (2026-07-19): modular plan with ZERO unchecked boxes must close —
# grep -c exits 1 on no matches, and pipefail killed the guard's count pipeline
TD="$(make_project)"; DIR="$TD/.context/plans/2026-07-19-clean-modular"
mkdir -p "$DIR"
write_plan "$DIR/00-index.md" "[x]"
printf '# Phase 1: Slice\n\n- [x] Task 1.1: done\n' > "$DIR/01-slice.md"
if ! (cd "$TD" && bash "$SCRIPT" 2026-07-19-clean-modular >/dev/null 2>&1); then
  fail "clean modular close failed (grep -c pipefail regression)"
fi
[[ -d "$TD/.context/plans/_archive/2026-07-19-clean-modular" ]] || fail "clean modular close did not archive"
rm -rf "$TD"

# --- BL-246: unreconciled in-text deferrals block the archive ---------------
#
# Four deferrals written as prose ("carry to Phase 6-7", "Phase 8 should note
# it") were never converted with the mechanism that exists, and vanished when
# their plan archived; two were still live. The archive is the last moment they
# are still visible, so it is the moment that has to check.

# 7. a bare in-text deferral -> blocked, plan stays in place
TD="$(make_project)"; PLAN="$TD/.context/plans/2026-07-19-guard.md"
write_plan "$PLAN" "[x]"
printf '\n- Bumping the rate limiter: carry this to Phase 7.\n' >> "$PLAN"
if (cd "$TD" && bash "$SCRIPT" 2026-07-19-guard >/dev/null 2>&1); then
  fail "close succeeded with an unreconciled in-text deferral"
fi
[[ -f "$PLAN" ]] || fail "blocked deferral close still moved the plan"

# 8. ...and --force is the escape, for a line that is prose ABOUT deferring
if ! (cd "$TD" && bash "$SCRIPT" 2026-07-19-guard --force >/dev/null 2>&1); then
  fail "--force did not bypass the deferral guard"
fi
rm -rf "$TD"

# 9. the same line carrying a BL-NNN closes: that is the mechanism working
TD="$(make_project)"; PLAN="$TD/.context/plans/2026-07-19-guard.md"
write_plan "$PLAN" "[x]"
printf '\n- Bumping the rate limiter: deferred to BL-412.\n' >> "$PLAN"
if ! (cd "$TD" && bash "$SCRIPT" 2026-07-19-guard >/dev/null 2>&1); then
  fail "a deferral referencing BL-412 was still blocked"
fi
rm -rf "$TD"

# 10. ...and so does an explicit CLOSE: with its reason
TD="$(make_project)"; PLAN="$TD/.context/plans/2026-07-19-guard.md"
write_plan "$PLAN" "[x]"
printf '\n- Follow-up on the cache warm-up. CLOSE: done inside Phase 3, nothing left.\n' >> "$PLAN"
if ! (cd "$TD" && bash "$SCRIPT" 2026-07-19-guard >/dev/null 2>&1); then
  fail "a deferral closed out with CLOSE: was still blocked"
fi
rm -rf "$TD"

# 11. a modular plan is scanned across ALL its files — the incident's deferrals
#     were in phase files, and the execution log lives in the index
TD="$(make_project)"; DIR="$TD/.context/plans/2026-07-19-modular-defer"
mkdir -p "$DIR"
write_plan "$DIR/00-index.md" "[x]"
printf '# Phase 1: Slice\n\n- [x] Task 1.1: done\n\nPhase 8 should note the index rebuild.\n' \
  > "$DIR/01-slice.md"
if (cd "$TD" && bash "$SCRIPT" 2026-07-19-modular-defer >/dev/null 2>&1); then
  fail "a deferral in a phase FILE did not block the close — only the index is being read"
fi
rm -rf "$TD"

# 12. a plan with no deferral phrasing at all still closes (no false positive on
#     the ordinary case, which is most of them)
TD="$(make_project)"; write_plan "$TD/.context/plans/2026-07-19-clean.md" "[x]"
if ! (cd "$TD" && bash "$SCRIPT" 2026-07-19-clean >/dev/null 2>&1); then
  fail "an ordinary plan with no deferrals was blocked by the deferral guard"
fi
[[ -f "$TD/.context/plans/_archive/2026-07-19-clean.md" ]] || fail "clean close did not archive"
rm -rf "$TD"

if [[ "$FAILS" -gt 0 ]]; then echo "FAIL ($FAILS)"; exit 1; fi
echo "OK — close-plan guard: 12 cells passed"
