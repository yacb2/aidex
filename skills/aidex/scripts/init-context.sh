#!/usr/bin/env bash
# init-context.sh — bootstrap .context/ in a project that doesn't have one yet.
#
# Usage: init-context.sh [project-dir]
#   project-dir   defaults to the current working directory.
#
# Idempotent: never overwrites anything that already exists. Prints one
# "created: <path>" or "exists: <path>" line per directory/file it considers.
#
# Steps:
#   1. Create .context/{backlog,plans,decisions,research,references,requests}/
#      plus backlog/_archive, plans/_archive, requests/_archive.
#   2. Seed indexes via the installed reindexers, when present:
#        $AIDEX_DIR/skills/aidex-backlog/scripts/register-item.sh --reindex
#        $AIDEX_DIR/skills/aidex-plan/scripts/reindex-plans.sh
#      Skipped (with a note) if the suite is not installed at $AIDEX_DIR
#      (default ~/.aidex).
#   3. Run $AIDEX_DIR/skills/aidex-conventions/scripts/detect-project-commands.sh
#      when present, writing its output to .context/references/project-commands.md
#      (skip-if-exists). Skipped (with a note) if not installed.
#   4. Print — never write — a suggested CLAUDE.md block. Editing CLAUDE.md is
#      the user's call.
#
# Always exits 0 (best-effort scaffolding; missing suite pieces are notes, not
# failures).

set -uo pipefail

AIDEX_DIR="${AIDEX_DIR:-$HOME/.aidex}"

PROJECT_DIR="${1:-$(pwd)}"
mkdir -p "$PROJECT_DIR"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"

CONTEXT_DIR="$PROJECT_DIR/.context"

note() { printf 'note: %s\n' "$*"; }

# --- Step 1: core skeleton ---

ensure_dir() {
  local dir="$1"
  local rel="${dir#"$PROJECT_DIR"/}"
  if [[ -d "$dir" ]]; then
    printf 'exists: %s\n' "$rel"
  else
    mkdir -p "$dir"
    printf 'created: %s\n' "$rel"
  fi
}

for d in backlog plans decisions research references requests; do
  ensure_dir "$CONTEXT_DIR/$d"
done
for d in backlog/_archive plans/_archive requests/_archive; do
  ensure_dir "$CONTEXT_DIR/$d"
done

# --- Step 1b: scratch bucket at the project root (claudemd-conventions.md
# § Scratch Output). One canonical name, so ephemeral output stops landing in
# .context/ or in a new ad-hoc folder per session. README is skip-if-exists.
ensure_dir "$PROJECT_DIR/_tmp"
TMP_README="$PROJECT_DIR/_tmp/README.md"
if [[ -f "$TMP_README" ]]; then
  printf 'exists: %s\n' "_tmp/README.md"
else
  cat > "$TMP_README" <<'EOF'
# _tmp — Disposable Artifacts

Single destination for ephemeral session output: verification screenshots,
diagnostic probes, consumed sync reports, scratch files.

**Contract**: anything in this folder can be deleted at any time without asking.
Do NOT create new ad-hoc folders at the workspace root for temporary artifacts.

If an artifact turns out to document a specific audit finding or bug worth
keeping long-term, move it into that audit's run folder
(`.context/audits/<methodology>/<run>/`) instead of leaving it here.
EOF
  printf 'created: %s\n' "_tmp/README.md"
fi

# --- Step 2: seed indexes via installed reindexers, when present ---

BACKLOG_REINDEX="$AIDEX_DIR/skills/aidex-backlog/scripts/register-item.sh"
if [[ -x "$BACKLOG_REINDEX" ]]; then
  ( cd "$PROJECT_DIR" && "$BACKLOG_REINDEX" --reindex ) >/dev/null 2>&1
  note "backlog index seeded via $BACKLOG_REINDEX --reindex"
else
  note "aidex-backlog not installed at $AIDEX_DIR — skipped backlog index seed"
fi

PLAN_REINDEX="$AIDEX_DIR/skills/aidex-plan/scripts/reindex-plans.sh"
if [[ -x "$PLAN_REINDEX" ]]; then
  ( cd "$PROJECT_DIR" && "$PLAN_REINDEX" --reindex ) >/dev/null 2>&1
  note "plans index seeded via $PLAN_REINDEX --reindex"
else
  note "aidex-plan not installed at $AIDEX_DIR — skipped plans index seed"
fi

# --- Step 3: detect project commands (skip-if-exists) ---

COMMANDS_OUT="$CONTEXT_DIR/references/project-commands.md"
DETECTOR="$AIDEX_DIR/skills/aidex-conventions/scripts/detect-project-commands.sh"
if [[ -f "$COMMANDS_OUT" ]]; then
  printf 'exists: %s\n' "${COMMANDS_OUT#"$PROJECT_DIR"/}"
elif [[ -x "$DETECTOR" ]]; then
  if "$DETECTOR" --project "$PROJECT_DIR" >"$COMMANDS_OUT" 2>/dev/null; then
    printf 'created: %s\n' "${COMMANDS_OUT#"$PROJECT_DIR"/}"
  else
    rm -f "$COMMANDS_OUT"
    note "detect-project-commands.sh failed — skipped ${COMMANDS_OUT#"$PROJECT_DIR"/}"
  fi
else
  note "aidex-conventions not installed at $AIDEX_DIR — skipped project-commands.md"
fi

# --- Step 4: print (never write) a suggested CLAUDE.md block ---

cat <<'EOF'

Suggested CLAUDE.md addition (review and add this yourself — never written automatically):

--------------------------------------------------------------------
## Project Conventions

This project uses `.context/` for planning artifacts (backlog, plans,
decisions, research, references, requests) per aidex conventions.
See `.context/references/project-commands.md` for detected review/commit/
release/test commands.
--------------------------------------------------------------------

EOF

exit 0
