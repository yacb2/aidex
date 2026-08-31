#!/usr/bin/env bash
# close-plan.sh — atomically close a plan (D-10): set status, record resolving
# commit(s), stamp `updated`, move the plan (modular dir or single file) to
# plans/_archive/. Handles both single-file and modular (dir + 00-index.md) plans.
#
# Usage:
#   close-plan.sh <slug | path> [options]
#
# Options:
#   --status <done|dropped>     default: done
#   --commit <sha>              resolving commit (repeatable). When work was
#                               escalated to this plan, commits live HERE (D-09).
#   --superseded-by <type/ref>  mark superseded (status stays; modifier records it)
#   --reason "<text>"           appended under a closing note
#   --force                     close as done even with unchecked checkboxes
#
# After closing, run `reconcile.sh` (Phase 6) to surface upstream backlog/findings
# that this plan resolved and may now be closeable.

set -euo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_GREEN=$'\033[32m' C_RED=$'\033[31m' C_RESET=$'\033[0m'
else C_GREEN='' C_RED='' C_RESET=''; fi
ok()  { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET" >&2; }
die() { printf '%serror: %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; exit 2; }

# Shared resolver. This file used to carry its own copy, three fixes behind:
# no $HOME boundary, no project-marker fallback, and no linked-worktree hop --
# so from inside a worktree it wrote into a directory that vanishes on teardown
# while _lib.sh consumers wrote to the main tree. Pinned by
# aidex-conventions/scripts/test-find-project-root.sh (no private copies).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

TARGET="" STATUS="done" SUPERSEDED="" REASON="" FORCE=0
COMMITS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)        STATUS="$2"; shift 2 ;;
    --commit)        COMMITS+=("$2"); shift 2 ;;
    --superseded-by) SUPERSEDED="$2"; shift 2 ;;
    --reason)        REASON="$2"; shift 2 ;;
    --force)         FORCE=1; shift ;;
    -h|--help)       sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*)              die "unknown option: $1" ;;
    *)               TARGET="$1"; shift ;;
  esac
done

[[ -n "$TARGET" ]] || die "target required: <slug | path>"
case "$STATUS" in done|dropped) ;; *) die "invalid --status: $STATUS (done|dropped)";; esac

ROOT="$(find_project_root)"
PLANS_DIR="$ROOT/.context/plans"

# --- resolve target to a plan (dir or single file) and its front-matter file ---
PLAN_PATH="" FM_FILE=""
if [[ -d "$TARGET" ]]; then PLAN_PATH="$TARGET"
elif [[ -f "$TARGET" ]]; then PLAN_PATH="$TARGET"
elif [[ -d "$PLANS_DIR/$TARGET" ]]; then PLAN_PATH="$PLANS_DIR/$TARGET"
elif [[ -f "$PLANS_DIR/$TARGET" ]]; then PLAN_PATH="$PLANS_DIR/$TARGET"
elif [[ -f "$PLANS_DIR/$TARGET.md" ]]; then PLAN_PATH="$PLANS_DIR/$TARGET.md"
else die "cannot resolve plan: $TARGET"; fi

if [[ -d "$PLAN_PATH" ]]; then
  FM_FILE="$PLAN_PATH/00-index.md"
  [[ -f "$FM_FILE" ]] || die "modular plan has no 00-index.md: $PLAN_PATH"
else
  FM_FILE="$PLAN_PATH"
fi

# guard: must live under plans/ active (not already in _archive)
case "$PLAN_PATH" in
  */_archive/*) die "plan already archived: $PLAN_PATH" ;;
esac

# consistency guard: closing as done with unchecked checkboxes means the
# front-matter and the phase checkpoints would disagree in the archive
if [[ "$STATUS" == "done" && "$FORCE" -eq 0 ]]; then
  if [[ -d "$PLAN_PATH" ]]; then
    UNCHECKED="$(grep -h -c '^\s*- \[ \]' "$PLAN_PATH"/*.md 2>/dev/null | awk '{s+=$1} END {print s+0}' || true)"
  else
    UNCHECKED="$(grep -c '^\s*- \[ \]' "$PLAN_PATH" 2>/dev/null || true)"
  fi
  if [[ "${UNCHECKED:-0}" -gt 0 ]]; then
    die "plan has $UNCHECKED unchecked checkbox(es) — closing as done would archive inconsistent state. Check them off, close with --status dropped, or pass --force"
  fi
fi

# Deferral reconciliation (BL-246). A plan carries deferrals as PROSE — "carry
# this to Phase 6-7", "Phase 8 should note it" — and the mechanism that makes one
# outlive the run already exists (`register-item.sh --origin plan`, whose
# `origin_ref: plan/<slug>` still resolves after the archive). Nothing connected
# the two: close-out reconciled nothing, so four deferrals written that way
# vanished the moment their plan archived, and two of them were still live.
#
# The check is per LINE and deliberately dumb: a line that reads as a deferral
# either names a `BL-NNN` or carries an explicit `CLOSE:` with the reason it
# needs neither. Anything cleverer would be a judgement this script cannot make,
# and `--force` is the escape for a line that is prose about deferring rather
# than a deferral.
#
# Modular plans are scanned across ALL their files, not just 00-index.md: the
# deferrals in the incident were in phase files, and the execution log is in the
# index — both have to be read.
if [[ "$FORCE" -eq 0 ]]; then
  if [[ -d "$PLAN_PATH" ]]; then
    DEFER_FILES=("$PLAN_PATH"/*.md)
  else
    DEFER_FILES=("$PLAN_PATH")
  fi
  UNRECONCILED="$(grep -n -H -i -E \
      '(defer(red|ral|rals|ring|s)?|carry (it |this |that )?(to|into)|later phase|follow-?up|should note)' \
      "${DEFER_FILES[@]}" 2>/dev/null | grep -v -E 'BL-[0-9]+|CLOSE:' || true)"
  if [[ -n "$UNRECONCILED" ]]; then
    printf '%serror: this plan has unreconciled deferral(s) — they would vanish with the archive:%s\n' \
      "$C_RED" "$C_RESET" >&2
    printf '%s\n' "$UNRECONCILED" | head -12 | sed 's/^/    /' >&2
    N_UNREC="$(printf '%s\n' "$UNRECONCILED" | wc -l | tr -d " ")"
    [[ "$N_UNREC" -gt 12 ]] && printf '    … and %s more\n' "$((N_UNREC - 12))" >&2
    die "reconcile each line before closing: register it with \`register-item.sh --origin plan --plan $(basename "$PLAN_PATH")\` and reference the BL-NNN on that line, or write an explicit \`CLOSE: <reason>\` on it. Pass --force only when the line is prose ABOUT deferring rather than a deferral"
  fi
fi

TODAY="$(date +%Y-%m-%d)"
COMMITS_STR="${COMMITS[*]:-}"

awk -v status="$STATUS" -v today="$TODAY" -v sup="$SUPERSEDED" -v commits="$COMMITS_STR" '
  BEGIN { d=0; infm=0; seen_sup=0; seen_commits=0 }
  /^---[[:space:]]*$/ {
    d++
    if (d==1) { infm=1; print; next }
    if (d==2) {
      if (sup!="" && !seen_sup) print "superseded_by: " sup
      if (commits!="" && !seen_commits) print "commits: \"" commits "\""
      infm=0; print; next
    }
  }
  infm==1 {
    if ($0 ~ /^status:/)  { print "status: " status; next }
    if ($0 ~ /^updated:/) { print "updated: " today; next }
    if (sup!="" && $0 ~ /^superseded_by:/) { print "superseded_by: " sup; seen_sup=1; next }
    if (commits!="" && $0 ~ /^commits:/) {
      val=$0; sub(/^commits:[[:space:]]*/,"",val); gsub(/"/,"",val)
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",val)
      if (val=="" || val=="[]") print "commits: \"" commits "\""
      else                      print "commits: \"" val " " commits "\""
      seen_commits=1; next
    }
    print; next
  }
  { print }
' "$FM_FILE" > "$FM_FILE.tmp" && mv "$FM_FILE.tmp" "$FM_FILE"

# keep the Session Checkpoint's **Status:** line in lockstep with front-matter
# (observed archive drift: front-matter done while the checkpoint still said open)
sed -E "s/^\*\*Status:\*\*[[:space:]].*/**Status:** $STATUS/" "$FM_FILE" > "$FM_FILE.tmp" && mv "$FM_FILE.tmp" "$FM_FILE"

[[ -n "$REASON" ]] && printf -- '\n> Closing note (%s): %s\n' "$TODAY" "$REASON" >> "$FM_FILE"

mkdir -p "$PLANS_DIR/_archive"
DEST="$PLANS_DIR/_archive/$(basename "$PLAN_PATH")"
[[ -e "$DEST" ]] && die "archive collision: $DEST already exists"
mv "$PLAN_PATH" "$DEST"
ok "Closed plan $(basename "$PLAN_PATH") → $STATUS · archived"
# Companions that did NOT travel inside the folder (a single-file plan's sibling
# page, or one that sat beside a modular plan rather than in it) follow it here.
archive_companions "$ROOT/.context" "plan/$(basename "$PLAN_PATH")" "$PLANS_DIR/_archive"
[[ -n "$COMMITS_STR" ]] && ok "  commits: $COMMITS_STR"

# Regenerate the plans roll-up index (00-index.md) so the closed plan moves to the
# Closed section. Best-effort: a missing reindexer never blocks the close.
REINDEX="$(dirname "${BASH_SOURCE[0]}")/reindex-plans.sh"
[[ -x "$REINDEX" ]] && bash "$REINDEX" >/dev/null 2>&1 || true

# Coverage boards. A plan close is the exact moment the coverage numbers change,
# and the boards under audits/test-coverage/ stayed stale until someone remembered
# to regenerate them by hand (ns_backoffice BL-197 → BL-274). When the project runs
# the test-coverage playbook (a module-map exists) regenerate coverage-matrix.md/.json
# and the run-level audits index here, so the boards and the closing note land in
# the same commit. No-op without a map. A failure is REPORTED, never swallowed and
# never a reason to undo the close: the archive already happened, and the red line
# is what gets the boards regenerated by hand before the close is committed.
COV_MAP="$ROOT/.context/audits/test-coverage/module-map.json"
AUDIT_SCRIPTS="$(dirname "${BASH_SOURCE[0]}")/../../aidex-audit/scripts"
if [[ -f "$COV_MAP" && -f "$AUDIT_SCRIPTS/coverage-matrix.sh" ]]; then
  COV_FAIL=""
  COV_OUT="$(bash "$AUDIT_SCRIPTS/coverage-matrix.sh" "$ROOT" 2>&1)" \
    || COV_FAIL+="    coverage-matrix.sh: ${COV_OUT##*$'\n'}"$'\n'
  IDX_OUT="$( (cd "$ROOT" && bash "$AUDIT_SCRIPTS/reindex-audits.sh") 2>&1)" \
    || COV_FAIL+="    reindex-audits.sh: ${IDX_OUT##*$'\n'}"$'\n'
  if [[ -z "$COV_FAIL" ]]; then
    ok "  coverage boards regenerated: audits/test-coverage/coverage-matrix.md (+.json), audits/00-index.md"
  else
    printf '%serror: coverage boards NOT regenerated — regenerate by hand before committing this close:%s\n%s' \
      "$C_RED" "$C_RESET" "$COV_FAIL" >&2
  fi
fi

# Surface backlog archive hygiene unprompted. A plan close is exactly when done
# backlog items tend to linger in the active folder (the "archive re-dictated 4x"
# friction): the sweep already lists them, so print that list here without being
# asked. Best-effort — a missing sweep never blocks the close.
SWEEP="$(dirname "${BASH_SOURCE[0]}")/../../aidex-backlog/scripts/sweep.sh"
if [[ -x "$SWEEP" ]]; then
  SWEEP_OUT="$( (cd "$ROOT" && NO_COLOR=1 bash "$SWEEP") 2>/dev/null || true)"
  if [[ "$SWEEP_OUT" == *"would archive"* ]]; then
    printf '\n%sBacklog: done/dropped items still in the active folder — archive them (D-10):%s\n' "$C_RED" "$C_RESET" >&2
    printf '%s\n' "$SWEEP_OUT" >&2
  fi
fi

printf '%s\n' "$DEST"
