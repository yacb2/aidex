#!/usr/bin/env bash
# check-overview.sh — mechanical doc-shape check for a worktree overview
# (.context/worktrees/00-index.md). Verifies the machine-consumed surface is
# intact so a broken doc is caught and amended in-session rather than passively
# recommended:
#   - front-matter has the worktree_up / worktree_down fields, NON-EMPTY
#   - the ## Procedure and ## Usage log sections are present
#   - the ## Running this worktree and ## Never run here sections are present
#   - the doc does not document the RETIRED tier mechanism
#   - every script the ## Procedure names actually exists
#   - every backlog/... path the doc references resolves (active / _archive /
#     _deferred)
#
# `## Running this worktree` / `## Never run here` are required because the
# forbidden set is PROJECT-SPECIFIC — a bare `playwright test` here, an
# un-offsettable Metro port there — so no shipped script can hold it. A doc that
# records topology and ports but not "what will hurt the main tree" leaves the
# only project-specific half of the contract to memory.
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
# Depends on _lib.sh (find_project_root / logging helpers) and wt-frontmatter.sh
# (the front-matter reader shared with worktree-multi.sh).

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/wt-frontmatter.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/wt-common.sh"

case "${1:-}" in -h|--help) wt_usage "${BASH_SOURCE[0]}"; exit 0 ;; esac

DOC="${1:-$(find_project_root)/.context/worktrees/00-index.md}"
[[ -f "$DOC" ]] || die "worktree overview not found: $DOC"

# .context/ is the doc's grandparent (.context/worktrees/00-index.md).
DOC_DIR="$(cd "$(dirname "$DOC")" && pwd -P)"
BACKLOG_DIR="$(dirname "$DOC_DIR")/backlog"

gaps=()

# --- front-matter fields (the LEADING --- ... --- block only) ---
# The same reader worktree-multi.sh uses (wt-frontmatter.sh): a `/^---$/,/^---$/` sed
# range reopens on every later pair of rules, so a field living in a body block
# passed here and the teardown then refused the doc.
fm="$(wt_fm_block "$DOC")"
# A field is only useful if it carries a command. `worktree_up: ""` is the shape
# a doc takes when its mechanism was retired and nobody updated the front-matter.
for field in worktree_up worktree_down; do
  line="$(grep -E "^${field}:" <<<"$fm" | sed -n 1p || true)"
  if [[ -z "$line" ]]; then
    gaps+=("front-matter: missing '$field' field")
  else
    raw="${line#*:}"; raw="${raw#"${raw%%[![:space:]]*}"}"
    val="$(wt_fm_unquote "$raw")"
    # A lone quote carries no command at all. Any other value the consumer's eval
    # cannot parse (an unclosed quote) would die at teardown: ask bash, which is
    # the parser the eval uses (with <slug>/<branch> placeholders filled, as the
    # callers do), rather than guessing from the first and last char.
    if [[ "$raw" =~ ^[\"\'] && ${#raw} -eq 1 ]]; then val=""
    elif ! bash -n <<<"$(sed -E 's/<[A-Za-z_-]+>/x/g' <<<"$val")" 2>/dev/null; then
      gaps+=("front-matter: '$field' has an unbalanced quote — the teardown eval would fail"); continue
    fi
    [[ -n "$val" ]] || gaps+=("front-matter: '$field' is empty — nothing to run")
  fi
done

# A script name resolves when it exists as written (after ~), or — if relative —
# under the project, or — for a bare basename written in prose, which is how the
# shipped scripts are normally referred to — under this skill. Reads PROJECT_DIR and
# SKILL_SCRIPTS, set below before either caller runs.
script_resolves() {
  local cand="${1/#\~/$HOME}"
  [[ -e "$cand" ]] && return 0
  [[ "$cand" != /* ]] && { [[ -e "$PROJECT_DIR/$cand" || -e "$SKILL_SCRIPTS/$(basename "$cand")" ]] && return 0; }
  return 1
}

# A front-matter command naming a script that does not resolve is a dead command
# (BL-627: the retired aidex-worktree skill path survives in owner docs).
# Resolved after SKILL_SCRIPTS is known, so bare `worktree.sh up <slug>` still passes.
fm_scripts_check() {
  local field s cand
  for field in worktree_new worktree_up worktree_down worktree_list; do
    # The retired skill path is judged on the raw token, in whatever spelling
    # (~, $HOME, ${CLAUDE_PLUGIN_ROOT}, absolute): the extractor below cannot
    # start a match at `/` or read through `{`, and its relative tail then
    # resolved against the shipped skill's basename.
    while IFS= read -r s; do
      [[ -z "$s" ]] && continue
      cand="${s/#\~/$HOME}"; cand="${cand/#\$HOME/$HOME}"
      [[ -e "$cand" ]] && continue
      gaps+=("front-matter: '$field' names a script that does not exist: $s (retired path; use \${CLAUDE_PLUGIN_ROOT}/skills/worktree/scripts/$(basename "$s"))")
    done < <(grep -E "^${field}:" <<<"$fm" | sed -n 1p | grep -oE '[^[:space:]"'"'"']*skills/aidex-worktree/[^[:space:]"'"'"']*\.sh' | sort -u || true)
    while IFS= read -r s; do
      [[ -z "$s" ]] && continue
      [[ "$s" == *skills/aidex-worktree/* ]] && continue
      script_resolves "$s" && continue
      gaps+=("front-matter: '$field' names a script that does not exist: $s")
    done < <(grep -E "^${field}:" <<<"$fm" | sed -n 1p | grep -oE '(~|[A-Za-z0-9_.$-])[A-Za-z0-9_./$-]*\.sh' | grep -v '\$' | sort -u || true)
  done
}

# --- required sections ---
grep -qE '^## +Procedure *$' "$DOC" || gaps+=("section: missing '## Procedure'")
grep -qE '^## +Usage log *$' "$DOC" || gaps+=("section: missing '## Usage log'")
grep -qE '^## +Running this worktree *$' "$DOC" \
  || gaps+=("section: missing '## Running this worktree'")
grep -qE '^## +Never run here *$' "$DOC" \
  || gaps+=("section: missing '## Never run here'")

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

PROJECT_DIR="$(dirname "$(dirname "$DOC_DIR")")"
SKILL_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
fm_scripts_check

# --- every script the Procedure names must exist ---
# Scoped to the Procedure section: the usage log legitimately names scripts that
# were removed years ago, and rewriting history is not the goal.
proc="$(awk '/^## +Procedure *$/{p=1;next} /^## /{p=0} p' "$DOC")"
while IFS= read -r s; do
  [[ -z "$s" ]] && continue
  script_resolves "$s" && continue
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
