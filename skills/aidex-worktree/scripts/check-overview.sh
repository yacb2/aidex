#!/usr/bin/env bash
# check-overview.sh — mechanical doc-shape check for a worktree overview
# (.context/worktrees/00-index.md). Verifies the machine-consumed surface is
# intact so a broken doc is caught and amended in-session rather than passively
# recommended:
#   - front-matter has the worktree_up / worktree_down fields, NON-EMPTY
#   - the ## Procedure and ## Usage log sections are present
#   - the doc does not document the RETIRED tier mechanism
#   - every script the ## Procedure names actually exists
#   - every backlog/... path the doc references resolves (active / _archive /
#     _deferred)
#
# The last three exist because presence checks alone certified three
# retired-mechanism docs as healthy. `worktree_up: ""` satisfied a
# `grep '^worktree_up:'`; a `## Tier decision` section was invisible; and a
# Procedure naming `_scripts/worktree-up.sh` passed while that script had never
# existed in that project. An agent following such a doc gets a checkout with no
# isolation and no failure signal — worse than a doc that is obviously broken.
# Non-zero exit lists the gaps (one per line, on stderr).
#
# Usage:
#   check-overview.sh [doc-path]
#
#   doc-path default: <project-root>/.context/worktrees/00-index.md
#
# Self-contained beyond _lib.sh (find_project_root / logging helpers).

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

DOC="${1:-$(find_project_root)/.context/worktrees/00-index.md}"
[[ -f "$DOC" ]] || die "worktree overview not found: $DOC"

# .context/ is the doc's grandparent (.context/worktrees/00-index.md).
DOC_DIR="$(cd "$(dirname "$DOC")" && pwd -P)"
BACKLOG_DIR="$(dirname "$DOC_DIR")/backlog"

gaps=()

# --- front-matter fields (first --- ... --- block) ---
fm="$(sed -n '/^---$/,/^---$/p' "$DOC")"
# A field is only useful if it carries a command. `worktree_up: ""` is the shape
# a doc takes when its mechanism was retired and nobody updated the front-matter.
for field in worktree_up worktree_down; do
  line="$(grep -E "^${field}:" <<<"$fm" | head -1 || true)"
  if [[ -z "$line" ]]; then
    gaps+=("front-matter: missing '$field' field")
  else
    val="${line#*:}"; val="${val#"${val%%[![:space:]]*}"}"      # strip leading space
    val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
    [[ -n "$val" ]] || gaps+=("front-matter: '$field' is empty — nothing to run")
  fi
done

# --- required sections ---
grep -qE '^## +Procedure *$' "$DOC" || gaps+=("section: missing '## Procedure'")
grep -qE '^## +Usage log *$' "$DOC" || gaps+=("section: missing '## Usage log'")

# --- the retired tier mechanism ---
# Anchored at the start of a heading on purpose: a usage-log entry titled
# "### 2026-07-23 — stem-streaming (Tier 2, slot 3)" is HISTORY and must stay
# readable. A "## Tier decision" section is PROCEDURE, and the procedure it
# describes no longer exists.
tier_heads="$(grep -nE '^#{2,4} +Tier' "$DOC" || true)"
if [[ -n "$tier_heads" ]]; then
  while IFS= read -r h; do
    gaps+=("retired mechanism: tier section at line ${h%%:*} — '${h#*:}' (there are no tiers; full isolation is the single path)")
  done <<<"$tier_heads"
fi

# --- every script the Procedure names must exist ---
# Scoped to the Procedure section: the usage log legitimately names scripts that
# were removed years ago, and rewriting history is not the goal.
proc="$(awk '/^## +Procedure *$/{p=1;next} /^## /{p=0} p' "$DOC")"
PROJECT_DIR="$(dirname "$(dirname "$DOC_DIR")")"
SKILL_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
while IFS= read -r s; do
  [[ -z "$s" ]] && continue
  cand="${s/#\~/$HOME}"
  [[ -e "$cand" ]] && continue
  if [[ "$cand" != /* ]]; then
    # Relative to the project, or — for a bare basename written in prose, which
    # is how the shipped scripts are normally referred to — to this skill.
    [[ -e "$PROJECT_DIR/$cand" ]] && continue
    [[ -e "$SKILL_SCRIPTS/$(basename "$cand")" ]] && continue
  fi
  gaps+=("## Procedure names a script that does not exist: $s")
done < <(grep -oE '(~|[A-Za-z0-9_.$-])[A-Za-z0-9_./$-]*\.sh' <<<"$proc" \
         | grep -v '\$' | sort -u)

# --- backlog references resolve (active / _archive / _deferred) ---
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  tail="${ref#backlog/}"
  base="$(basename "$ref")"
  if [[ -e "$BACKLOG_DIR/$tail" || -e "$BACKLOG_DIR/_archive/$base" || -e "$BACKLOG_DIR/_deferred/$base" ]]; then
    continue
  fi
  gaps+=("backlog ref does not resolve: $ref")
done < <(grep -oE 'backlog/[A-Za-z0-9._/-]+\.md' "$DOC" | sort -u)

if [[ ${#gaps[@]} -gt 0 ]]; then
  err "doc-shape check FAILED (${#gaps[@]} gap(s)): $DOC"
  for g in "${gaps[@]}"; do printf '  - %s\n' "$g" >&2; done
  exit 1
fi

ok "doc-shape OK: $DOC"
