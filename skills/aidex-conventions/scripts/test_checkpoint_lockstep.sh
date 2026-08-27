#!/usr/bin/env bash
# Lockstep guard for the between-unit checkpoint.
#
# One owner — references/checkpoint-conventions.md — and two consumers that must delegate
# to it rather than restate it:
#
#   1. aidex-plan-exec/SKILL.md   (§2, between phases)
#   2. aidex-backlog/SKILL.md     (sweep run mode, every ~5 items / cluster boundary)
#
# Three cells, all DERIVED from the files — nothing here hard-codes the four moves. A guard
# that names what it guards rots the moment the owner edits it (two repo tests were found
# silently dead this way on 2026-07-24). What is checked is the property that made the
# extraction necessary: the load-bearing parts live in ONE place, and each consumer points
# at it instead of carrying a numbered copy that drifts.
#
# Consumers are line-wrapped prose; every match runs over a whitespace-flattened copy so a
# reflow never reads as a failure.
#
# Run with: bash skills/aidex-conventions/scripts/test_checkpoint_lockstep.sh

set -uo pipefail

SKILLS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CANON="${CANON_OVERRIDE:-$SKILLS/aidex-conventions/references/checkpoint-conventions.md}"
EXEC="${EXEC_OVERRIDE:-$SKILLS/aidex-plan-exec/SKILL.md}"
SWEEP="${SWEEP_OVERRIDE:-$SKILLS/aidex-backlog/SKILL.md}"

fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }
die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
for f in "$CANON" "$EXEC" "$SWEEP"; do [ -f "$f" ] || die "missing file: $f"; done
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
CANON_FLAT="$(flat "$CANON")"; EXEC_FLAT="$(flat "$EXEC")"; SWEEP_FLAT="$(flat "$SWEEP")"

# ---------- cell 1: the canon carries the load-bearing parts ----------
case "$CANON_FLAT" in *resolve-review-scope.sh*) ;; *) err "canon does not name the review-scope resolver" ;; esac
case "$CANON_FLAT" in *"Exit 3"*|*"exit 3"*) ;; *) err "canon does not state the exit-3 (empty scope is never a passing review) rule" ;; esac
case "$CANON_FLAT" in *"review: <verdict>"*"anchor=<anchor>"*) ;; *) err "canon does not carry the anchored Execution-log line (review: <verdict> · <n> findings · scope=<scope> anchor=<anchor>)" ;; esac
case "$CANON_FLAT" in *"merge base"*|*"merge-base"*) ;; *) err "canon does not say the scope is resolved from the merge base when the unit spans commits" ;; esac
case "$CANON_FLAT" in *"--origin"*) ;; *) err "canon does not name register-item.sh --origin for emergent work" ;; esac
case "$CANON_FLAT" in *"never a question"*|*"never asked"*|*"do not ask"*) ;; *) err "canon does not make the handoff a mandated step rather than a question" ;; esac
# the resolver path the canon tells an installed user to run must exist
named=$(printf '%s' "$CANON_FLAT" | tr ' `' '\n\n' | grep 'resolve-review-scope\.sh' | head -1)
if [ -n "$named" ]; then
  [ -f "$SKILLS/aidex-conventions/scripts/$(basename "$named")" ] || err "canon names '$named' but no such script exists"
fi

# ---------- cell 2: plan-exec delegates and carries NO numbered restatement ----------
case "$EXEC_FLAT" in *checkpoint-conventions.md*) ;; *) err "aidex-plan-exec/SKILL.md does not reference checkpoint-conventions.md — the consumer is free to drift" ;; esac
# The §2 section, isolated: a numbered list restating the moves is what the extraction
# removed. Count numbered items in that section whose text carries a move keyword; the
# canon has four, so a consumer with 2+ has started its own copy.
sec2="$(awk '/^### 2\. /{f=1} /^### 3\. /{f=0} f' "$EXEC")"
[ -n "$sec2" ] || err "aidex-plan-exec/SKILL.md has no '### 2.' checkpoint section to check"
restated="$(printf '%s\n' "$sec2" | grep -cE '^[0-9]+\. \*\*(Code-review|Commit|Defer|Context check)' || true)"
[ "${restated:-0}" -lt 2 ] || err "aidex-plan-exec/SKILL.md §2 restates $restated of the four moves as its own numbered list — point at the canon instead"

# ---------- cell 3: the sweep consumer points at the same file and names its cadence ----------
case "$SWEEP_FLAT" in *checkpoint-conventions.md*) ;; *) err "aidex-backlog/SKILL.md (sweep run mode) does not reference checkpoint-conventions.md" ;; esac
case "$SWEEP_FLAT" in *"5 items"*) ;; *) err "aidex-backlog/SKILL.md does not name the sweep checkpoint cadence (~5 items)" ;; esac
case "$SWEEP_FLAT" in *"exit code"*) ;; *) err "aidex-backlog/SKILL.md does not name what the sweep seed adds (what ran, with which exit codes)" ;; esac

# ---------- and the canon is reachable from the hub ----------
grep -q "references/checkpoint-conventions.md" "$SKILLS/aidex-conventions/SKILL.md" \
  || err "checkpoint-conventions.md is not routed from aidex-conventions/SKILL.md — unreachable canon"

[ "$fail" -eq 0 ] && echo "OK — checkpoint canon and its two consumers are in lockstep"
exit "$fail"
