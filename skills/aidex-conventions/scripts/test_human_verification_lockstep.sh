#!/usr/bin/env bash
# Lockstep guard for guided human verification (BL-228).
#
# The protocol has one owner — references/human-verification-conventions.md — and two
# consumers that must delegate to it rather than restate it:
#
#   1. aidex-plan-exec/references/02-close-out.md   (close-out step 7)
#   2. aidex-bugfix/SKILL.md                        (step 8)
#   3. aidex-backlog/references/sweep-execution-policy.md (sweep close-out) — its proof
#      artifact is the items' owner rows aggregated by the report, NOT a per-item
#      human-verification.md; amended in as a consumer, never carved out
#
# What is guarded is NOT the four moves. Those were already written down, twice, and
# still went missing. What is guarded is the property that makes the step survive
# contact with a real run:
#
#   a skip is RECORDED, never silent.
#
# Hence the cells below. The canon must say a skip is recorded and must not carry a
# bare carve-out clause; each consumer must name the canon, name the proof artifact,
# and name the recorded skip. The failure mode this catches is not deletion — nobody
# deletes a verification step. It is the reappearance of an innocent-looking
# "skip for pure backend/tooling work" line, which reads as a legitimate exemption and
# quietly removes the only thing distinguishing "nothing to check" from "nobody looked".
#
# Set CANON_OVERRIDE / EXEC_OVERRIDE / FIX_OVERRIDE to point a cell at a mutated copy
# (that is how the RED is demonstrated without writing junk under skills/).
#
# Run with: bash skills/aidex-conventions/scripts/test_human_verification_lockstep.sh

set -uo pipefail

SKILLS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
CANON="${CANON_OVERRIDE:-$SKILLS/aidex-conventions/references/human-verification-conventions.md}"
EXEC="${EXEC_OVERRIDE:-$SKILLS/aidex-plan-exec/references/02-close-out.md}"
FIX="${FIX_OVERRIDE:-$SKILLS/aidex-bugfix/SKILL.md}"
SWEEP="${SWEEP_OVERRIDE:-$SKILLS/aidex-backlog/references/sweep-execution-policy.md}"

fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }
die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for f in "$CANON" "$EXEC" "$FIX" "$SWEEP"; do
  [ -f "$f" ] || die "missing file: $f"
done

# Consumers are line-wrapped prose; match against a whitespace-flattened copy so a
# reflow never turns into a false failure.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
CANON_FLAT="$(flat "$CANON")"
EXEC_FLAT="$(flat "$EXEC")"
FIX_FLAT="$(flat "$FIX")"
SWEEP_FLAT="$(flat "$SWEEP")"

# ---------- the canon states where it fires and what a skip costs ----------
case "$CANON_FLAT" in
  *"integration boundary"*) ;;
  *) err "canon does not name the integration boundary — the step has no gate to hang on" ;;
esac
case "$CANON_FLAT" in
  *"end of a run"*) ;;
  *) err "canon does not include the end of a run in the boundary; close-out does not merge, so a step sited only at the merge never fires" ;;
esac
case "$CANON_FLAT" in
  *"proofs/<slug>"*) ;;
  *) err "canon names no proof artifact path — the verification would vanish with the session" ;;
esac
case "$CANON_FLAT" in
  *"proof_links"*) ;;
  *) err "canon does not link the artifact from proof_links" ;;
esac
case "$CANON_FLAT" in
  *"Skipping silently is not"*|*"skipped silently"*|*"never silently"*) ;;
  *) err "canon does not state that a silent skip is disallowed" ;;
esac

# ---------- the bare carve-out must not come back, in the canon or either consumer --
# The exact clause BL-228 removed. It is allowed to APPEAR while being named as the
# failure (the canon quotes it to forbid it), so a bare occurrence is one that is not
# accompanied by a word rejecting it.
for pair in "canon:$CANON" "close-out:$EXEC" "bugfix:$FIX" "sweep:$SWEEP"; do
  label="${pair%%:*}"; file="${pair#*:}"
  while IFS= read -r line; do
    case "$line" in
      *"skip for pure backend"*|*"skip for backend"*)
        case "$line" in
          *forbid*|*failure*|*not*|*never*|*bare*) ;;
          *) err "$label carries a bare carve-out clause: '$line' — an unrecorded skip is the defect, not an exemption" ;;
        esac
        ;;
    esac
  done < "$file"
done

# ---------- each consumer delegates, and names the two things it gets wrong from memory
for pair in "close-out:$EXEC_FLAT" "bugfix:$FIX_FLAT"; do
  label="${pair%%:*}"; body="${pair#*:}"
  case "$body" in
    *human-verification-conventions.md*) ;;
    *) err "$label does not point at human-verification-conventions.md — a restated protocol is a second place to drift" ;;
  esac
  case "$body" in
    *"human-verification.md"*) ;;
    *) err "$label does not name the proof artifact it must write" ;;
  esac
  case "$body" in
    *"human-verification: skipped"*) ;;
    *) err "$label does not carry the recorded-skip line, so a skip there is indistinguishable from an omission" ;;
  esac
done

# ---------- the sweep consumer: same three properties, its own proof artifact ----------
case "$SWEEP_FLAT" in
  *human-verification-conventions.md*) ;;
  *) err "sweep policy does not point at human-verification-conventions.md" ;;
esac
case "$SWEEP_FLAT" in
  *"owner"*"sweep-report"*|*"sweep-report"*"owner"*) ;;
  *) err "sweep policy does not name its proof artifact (the items' owner rows aggregated by sweep-report.sh)" ;;
esac
case "$SWEEP_FLAT" in
  *"human-verification: skipped"*) ;;
  *) err "sweep policy does not carry the recorded-skip line" ;;
esac
# and the canon itself names the sweep shape, so the third consumer is amended in, not exempted
case "$CANON_FLAT" in
  *"sweep-report"*) ;;
  *) err "canon does not name the sweep's proof artifact — a consumer the canon does not know is a carve-out" ;;
esac

# ---------- bugfix counts its own steps ----------
# The step list is prose with a stated count; adding a step without moving the count
# leaves a reader trusting the smaller number.
steps=$(grep -cE '^[0-9]+\. ' "$FIX")
case "$FIX_FLAT" in
  *"these eight steps"*) [ "$steps" -ge 8 ] || err "aidex-bugfix says eight steps but lists $steps" ;;
  *) err "aidex-bugfix's stated step count does not include the human-verification step" ;;
esac

[ "$fail" -eq 0 ] && echo "OK — human-verification canon and its three consumers are in lockstep"
exit "$fail"
