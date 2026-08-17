#!/usr/bin/env bash
# close-audit.sh — archive an audit RUN folder on cycle close (D-10). The rolling
# 00-inventory.md stays as a live board; only the completed run folder moves to
# <audits-base>/_archive/. Refuses if the run still has unresolved in-scope
# findings, unless --force.
#
# Usage:
#   close-audit.sh <run-slug | run-path> [--force]
#
# "Resolved" finding statuses: closed, done, escalated, fixed, dropped, wontfix.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$SCRIPT_DIR/_lib.sh"

TARGET="" FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)   FORCE=1; shift ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*)        die "unknown option: $1" ;;
    *)         TARGET="$1"; shift ;;
  esac
done
[[ -n "$TARGET" ]] || die "run required: <run-slug | run-path>"

ROOT="$(find_project_root)"
AUDITS_DIR="$ROOT/.context/audits"

# --- resolve run folder ---
RUN_PATH=""
if [[ -d "$TARGET" ]]; then RUN_PATH="$TARGET"
elif [[ -d "$AUDITS_DIR/$TARGET" ]]; then RUN_PATH="$AUDITS_DIR/$TARGET"
else RUN_PATH="$(find "$AUDITS_DIR" -maxdepth 2 -type d -name "$TARGET" 2>/dev/null | grep -v '/_archive/' | head -1)"; fi
[[ -n "$RUN_PATH" && -d "$RUN_PATH" ]] || die "cannot resolve audit run: $TARGET"
case "$RUN_PATH" in */_archive/*) die "run already archived: $RUN_PATH" ;; esac

RUN_SLUG="$(basename "$RUN_PATH")"
PARENT="$(dirname "$RUN_PATH")"

# --- locate the governing inventory (run's parent, else audits root) ---
INV=""
[[ -f "$PARENT/00-inventory.md" ]] && INV="$PARENT/00-inventory.md"
[[ -z "$INV" && -f "$AUDITS_DIR/00-inventory.md" ]] && INV="$AUDITS_DIR/00-inventory.md"

# --- check in-scope findings for this run ---
# Canon Audit Runs cell holds comma-separated DATES (audit-conventions.md); legacy
# boards recorded run SLUGS. Match either: the run folder's date prefix or its slug.
RUN_DATE="${RUN_SLUG:0:10}"
if [[ -n "$INV" ]]; then
  UNRESOLVED="$(awk -F'|' -v run="$RUN_SLUG" -v rundate="$RUN_DATE" '
    /^\|/ {
      # Audit Runs is column 7 of 9 (NF==11 with the empty edges) since BL-057, and
      # column 9 of 11 on pre-2026-08-06 boards (NF==13). Pick by width rather than
      # assuming: reading $10 on a 9-column board silently reads Escalated To, and
      # every finding then looks out of scope.
      id=$2; status=$6; runs=(NF >= 13 ? $10 : $8)
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",id)
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",status)
      if (id=="" || id=="ID") next
      if (index(runs, run)==0 && index(runs, rundate)==0) next
      resolved=" closed done escalated fixed dropped wontfix "
      if (index(resolved, " " status " ")==0) print "    - " id " (" status ")"
    }' "$INV")"
  if [[ -n "$UNRESOLVED" ]]; then
    warn "Run '$RUN_SLUG' has unresolved in-scope findings:"
    printf '%s\n' "$UNRESOLVED" >&2
    if [[ $FORCE -eq 0 ]]; then
      die "refusing to archive (use --force to override, e.g. for upstream/out-of-scope findings)"
    fi
    warn "--force given: archiving anyway."
  fi
else
  warn "no 00-inventory.md found near run; skipping finding check"
fi

# --- archive the run folder ---
mkdir -p "$PARENT/_archive"
DEST="$PARENT/_archive/$RUN_SLUG"
[[ -e "$DEST" ]] && die "archive collision: $DEST already exists"
mv "$RUN_PATH" "$DEST"
# $DEST itself, not a path reassembled from its own dirname: `dirname "$DEST"`
# is already <parent>/_archive, so appending /_archive/ printed a doubled path
# that does not exist. The archive landed correctly; the line describing it did
# not, which is the same class of defect as a check that misreports its result.
ok "Archived audit run '$RUN_SLUG' → $DEST"

# Regenerate the audits run-level roll-up so the closed run moves to Archived runs.
# Best-effort: a missing reindexer never blocks the close.
REINDEX="$SCRIPT_DIR/reindex-audits.sh"
[[ -x "$REINDEX" ]] && bash "$REINDEX" >/dev/null 2>&1 || true

printf '%s\n' "$DEST"
