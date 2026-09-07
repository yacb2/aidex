#!/usr/bin/env bash
# init-context.sh — bootstrap .context/ in a project that doesn't have one yet.
#
# Usage: init-context.sh [project-dir] [--artifact-style <lang> | --no-artifact-style]
#   project-dir              defaults to the current working directory.
#   --artifact-style <lang>  explicit yes to the artifact style profile, in that
#                            language (an ISO code: en, es, fr...).
#   --no-artifact-style      explicit decline; recorded so nothing asks twice.
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
#      (default ~/.claude, where install.sh puts the suite).
#   3. Run $AIDEX_DIR/skills/aidex-conventions/scripts/detect-project-commands.sh
#      when present, writing its output to .context/references/01-project-commands.md
#      (skip-if-exists). Skipped (with a note) if not installed.
#   4. Offer .context/artifact-style.md — the ONE question init asks. Created
#      only on an explicit yes (the --artifact-style flag, or a non-empty answer
#      at a TTY); a decline is recorded in .context/.aidex-artifact-style-offered,
#      the same marker aidex-dash's wrap-time offer uses, so neither surface asks
#      twice. With no flag and no TTY the question is SKIPPED and said to be
#      skipped — no profile, and no marker either, because skipped is not asked
#      and silencing the wrap-time offer here would lose the question entirely.
#   5. Print — never write — a suggested CLAUDE.md block. Editing CLAUDE.md is
#      the user's call.
#
# Always exits 0 (best-effort scaffolding; missing suite pieces are notes, not
# failures).

set -uo pipefail

AIDEX_DIR="${AIDEX_DIR:-$HOME/.claude}"

PROJECT_DIR=""
STYLE_LANG=""          # non-empty => explicit yes, in this language
STYLE_DECLINED=0       # 1 => explicit no
while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-style)
      [[ $# -ge 2 ]] || { printf 'error: --artifact-style needs a language code\n' >&2; exit 2; }
      STYLE_LANG="$2"; shift 2 ;;
    --artifact-style=*) STYLE_LANG="${1#*=}"; shift ;;
    # A separate flag rather than `--artifact-style no`: `no` is Norwegian's
    # ISO 639-1 code, so a decline spelled as a value collides with a language.
    --no-artifact-style) STYLE_DECLINED=1; shift ;;
    -*) printf 'error: unknown option: %s\n' "$1" >&2; exit 2 ;;
    *) PROJECT_DIR="$1"; shift ;;
  esac
done

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
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
for d in backlog/_archive plans/_archive requests/_archive decisions/_archive; do
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

# The reference tier accepts NN-<slug>.md (validate.py) — a bare
# project-commands.md is read as a dated artifact and fails the filename rule.
# The detector emits bare `key: value` lines, so the front-matter every artifact
# needs is added here, around it.
COMMANDS_OUT="$CONTEXT_DIR/references/01-project-commands.md"
COMMANDS_LEGACY="$CONTEXT_DIR/references/project-commands.md"
DETECTOR="$AIDEX_DIR/skills/aidex-conventions/scripts/detect-project-commands.sh"
if [[ -f "$COMMANDS_OUT" ]]; then
  printf 'exists: %s\n' "${COMMANDS_OUT#"$PROJECT_DIR"/}"
elif [[ -f "$COMMANDS_LEGACY" ]]; then
  # Pre-existing project from before the rename: leave it alone, never duplicate.
  printf 'exists: %s\n' "${COMMANDS_LEGACY#"$PROJECT_DIR"/}"
elif [[ -x "$DETECTOR" ]]; then
  DETECTED="$("$DETECTOR" --project "$PROJECT_DIR" 2>/dev/null)"
  if [[ -n "$DETECTED" ]]; then
    TODAY="$(date +%F)"
    {
      printf -- '---\n'
      printf 'title: "Project commands"\n'
      printf 'status: living\n'
      printf 'created: %s\n' "$TODAY"
      printf 'updated: %s\n' "$TODAY"
      printf -- '---\n\n'
      printf '# Project commands\n\n'
      printf 'Detected by `detect-project-commands.sh` at init. Correct any\n'
      printf '`(not detected)` line by hand — the tooling reads these values.\n\n'
      printf '```\n%s\n```\n' "$DETECTED"
    } > "$COMMANDS_OUT"
    printf 'created: %s\n' "${COMMANDS_OUT#"$PROJECT_DIR"/}"
  else
    note "detect-project-commands.sh failed — skipped ${COMMANDS_OUT#"$PROJECT_DIR"/}"
  fi
else
  note "aidex-conventions not installed at $AIDEX_DIR — skipped 01-project-commands.md"
fi

# --- Step 4: the one question — .context/artifact-style.md ---
#
# Why it lives here and not only in aidex-dash's wrap-time offer: the wrap fires
# MID-TASK, when the user is being handed an artifact and not being set up. A
# usage-retro measured it at 14 firings across 7 projects with 6 ignored. Init is
# the opposite context — the user is present and expecting setup questions.
#
# What this does NOT do is overturn "the profile is never auto-created" (e87bbd3,
# 02-local-first-artifacts.md § "If absent, never create it silently"). It moves
# the QUESTION, and still writes the file only on an explicit yes.
#
# The record of a decline is the SAME marker aidex-dash writes
# (wrap_report.py OFFER_MARKER), not a second one, so a decline here silences the
# wrap-time offer and vice versa — neither surface asks twice.

STYLE_PROFILE="$CONTEXT_DIR/artifact-style.md"
STYLE_MARKER="$CONTEXT_DIR/.aidex-artifact-style-offered"
STYLE_TEMPLATE="$AIDEX_DIR/skills/aidex-dash/assets/templates/artifact-style.md.template"

record_style_offer() {
  # Same filename, same meaning, same closing sentence as wrap_report.py's, so
  # either writer's marker reads as the record the other one looks for.
  cat > "$STYLE_MARKER" <<'MARKEREOF'
The artifact style profile was offered once, at `/aidex init`. Delete this file to offer it again.
MARKEREOF
}

write_style_profile() {
  local lang="$1"
  # The template's own `- language: en` is the field wrap-report.sh parses;
  # substituting it is the whole point of asking. Every other {{...}} placeholder
  # is left for the human — inventing a palette here is what the profile exists
  # to stop.
  sed -e "s|{{PROJECT_NAME}}|$(basename "$PROJECT_DIR")|g" \
      -e "s|^- language: en$|- language: ${lang}|" \
      "$STYLE_TEMPLATE" > "$STYLE_PROFILE"
}

if [[ -f "$STYLE_PROFILE" ]]; then
  printf 'exists: %s\n' "${STYLE_PROFILE#"$PROJECT_DIR"/}"
elif [[ ! -f "$STYLE_TEMPLATE" ]]; then
  note "aidex-dash not installed at $AIDEX_DIR — skipped the artifact-style.md question"
elif [[ -n "$STYLE_LANG" ]]; then
  # An explicit flag is an explicit yes, marker or not: the marker gates the
  # QUESTION, never an answer the caller already gave.
  write_style_profile "$STYLE_LANG"
  record_style_offer
  printf 'created: %s\n' "${STYLE_PROFILE#"$PROJECT_DIR"/}"
  note "artifact language set to '$STYLE_LANG' — .context/ itself stays English (D-04)"
elif [[ "$STYLE_DECLINED" -eq 1 ]]; then
  record_style_offer
  note "artifact-style.md declined — recorded in ${STYLE_MARKER#"$PROJECT_DIR"/}, so the wrap-time offer will not ask again"
elif [[ -f "$STYLE_MARKER" ]]; then
  note "artifact-style.md was offered before (${STYLE_MARKER#"$PROJECT_DIR"/}) — not asking again"
elif [[ -t 0 ]]; then
  printf '\nArtifacts (HTML reports, dashboards) render from .context/artifact-style.md.\n' >&2
  printf 'Create it? Enter the artifact language code (e.g. en, es) — empty declines: ' >&2
  read -r STYLE_REPLY
  record_style_offer
  if [[ -n "$STYLE_REPLY" ]]; then
    write_style_profile "$STYLE_REPLY"
    printf 'created: %s\n' "${STYLE_PROFILE#"$PROJECT_DIR"/}"
    note "artifact language set to '$STYLE_REPLY' — .context/ itself stays English (D-04)"
  else
    note "artifact-style.md declined — recorded in ${STYLE_MARKER#"$PROJECT_DIR"/}, so the wrap-time offer will not ask again"
  fi
else
  # No flag and no TTY — which is every run through Claude Code's Bash tool, so
  # this note is the handoff: it tells the caller to ask the one question and
  # re-run with the answer (init is idempotent, so the re-run costs nothing).
  # No marker is written: skipped is not asked, and writing one here would
  # silence aidex-dash's wrap-time offer for every headlessly bootstrapped
  # project — losing the question at both surfaces instead of moving it.
  note "no TTY — skipped the artifact-style.md question; no profile created. Ask the user for the artifact language, then re-run with --artifact-style <lang> (or --no-artifact-style to record a decline)"
fi

# --- Step 5: print (never write) a suggested CLAUDE.md block ---

cat <<'EOF'

Suggested CLAUDE.md addition (review and add this yourself — never written automatically):

--------------------------------------------------------------------
## Project Conventions

This project uses `.context/` for planning artifacts (backlog, plans,
decisions, research, references, requests) per aidex conventions.
See `.context/references/01-project-commands.md` for detected review/commit/
release/test commands.

Ephemeral output (screenshots, probes, scratch files) goes in `_tmp/`.
Anything there is deletable without asking.
--------------------------------------------------------------------

Suggested .gitignore addition (also never written automatically) — the scratch
contents are disposable, but the contract README is worth tracking:

--------------------------------------------------------------------
_tmp/*
!_tmp/README.md
--------------------------------------------------------------------

EOF

exit 0
