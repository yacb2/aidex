#!/usr/bin/env bash
# new-audit.sh — scaffold a new audit run in the CANON layout (D-02 + the
# 2026-07-02 rebuild decisions).
#
# Usage:
#   new-audit.sh <type> <slug>          # methodology run: audits/<type>/YYYY-MM-DD-<slug>/
#   new-audit.sh --standalone <slug>    # one-shot run:    audits/YYYY-MM-DD-<slug>/ (no boards)
#
#   <type>: ux, ai-opportunities, security, perf, a11y, hitl, retest, custom
#           (legacy aliases like ux-audit / ia-opportunities are normalized)
#   <slug>: kebab-case identifier, e.g. "login-redesign"
#
# Methodology runs get the three per-methodology boards on first use:
#   audits/<type>/00-inventory.md · 00-methodology.md (seeded from the type's
#   playbook template) · 00-changelog.md — never at the audits/ root.
# Standalone runs (canon §Standalone one-shot runs) get only a dated folder
# with index.md; escalation uses origin_ref: audit/<run>/<finding-id>.

set -euo pipefail
. "$(dirname "$0")/_lib.sh"

# Strip leading "new" if the skill dispatcher passed full args
if [[ "${1:-}" == "new" ]]; then shift; fi

usage() {
  cat <<EOF >&2
Usage: /aidex-audit new <type> <slug>
       /aidex-audit new --standalone <slug>

Types: ux, ai-opportunities, security, perf, a11y, hitl, retest, custom
       (legacy -audit-suffixed names accepted as aliases)

Examples:
  /aidex-audit new ux login-redesign
  /aidex-audit new --standalone usage-retro-q3
EOF
  exit 2
}

[[ $# -lt 2 ]] && usage

STANDALONE=0
if [[ "$1" == "--standalone" ]]; then
  STANDALONE=1
  SLUG="$2"
else
  TYPE_INPUT="$1"
  SLUG="$2"
fi

is_valid_slug "$SLUG" || die "invalid slug: $SLUG (use kebab-case: lowercase letters, digits, hyphens)"

ROOT="$(find_project_root)"
AUDITS_DIR="$ROOT/.context/audits"
DATE_ISO="$(today_iso)"
PROJECT_NAME="$(basename "$ROOT")"

# ---------- standalone one-shot: dated run at audits/ root, no boards ----------
if [[ "$STANDALONE" -eq 1 ]]; then
  RUN_DIR="$AUDITS_DIR/$DATE_ISO-$SLUG"
  [[ -e "$RUN_DIR" ]] && die "audit run already exists: $RUN_DIR"
  mkdir -p "$RUN_DIR"
  cat > "$RUN_DIR/index.md" <<EOF
---
title: "Standalone analysis — $SLUG"
status: doing
created: $DATE_ISO
updated: $DATE_ISO
methodology: standalone
---

# Standalone analysis — $SLUG

**Scope:** <!-- what this one-shot analysis covers -->
**Method:** <!-- how it was produced (agents, scripts, manual walkthrough) -->

## Summary

<!-- One paragraph, written AFTER the analysis. -->

## Findings

<!-- Findings that outlive this analysis escalate to backlog with
     origin_ref: audit/$DATE_ISO-$SLUG/<finding-id> (no methodology segment). -->

## Disposition

<!-- Where each actionable finding went: backlog items, plans, decisions. -->
EOF
  REINDEX="$(dirname "${BASH_SOURCE[0]}")/reindex-audits.sh"
  [[ -x "$REINDEX" ]] && bash "$REINDEX" >/dev/null 2>&1 || true
  ok "Standalone audit run scaffolded: $RUN_DIR"
  echo "$RUN_DIR"
  exit 0
fi

# ---------- methodology run: audits/<type>/YYYY-MM-DD-<slug>/ ----------
TYPE="$(normalize_type "$TYPE_INPUT")" || die "unknown type: $TYPE_INPUT (valid: ${AUDIT_TYPES[*]} — legacy -audit names accepted)"

# For custom, the methodology folder takes the slug as its name.
METHODOLOGY="$TYPE"
[[ "$TYPE" == "custom" ]] && METHODOLOGY="$SLUG"
M_NAME="$(methodology_name "$METHODOLOGY")"

M_DIR="$AUDITS_DIR/$METHODOLOGY"
RUN_DIR="$M_DIR/$DATE_ISO-$SLUG"
[[ -e "$RUN_DIR" ]] && die "audit run already exists: $RUN_DIR"
mkdir -p "$M_DIR"

# Boards on first use of the methodology — inside the methodology folder (D-02).
if [[ ! -f "$M_DIR/00-inventory.md" ]]; then
  info "Creating $METHODOLOGY/00-inventory.md"
  render_template "$TEMPLATES_DIR/00-inventory.md.template" "$M_DIR/00-inventory.md" \
    PROJECT_NAME="$PROJECT_NAME" DATE="$DATE_ISO" METHODOLOGY="$METHODOLOGY" METHODOLOGY_NAME="$M_NAME"
fi

if [[ ! -f "$M_DIR/00-methodology.md" ]]; then
  PLAYBOOK_TEMPLATE="$TEMPLATES_DIR/methodology/$TYPE.md.template"
  if [[ -f "$PLAYBOOK_TEMPLATE" ]]; then
    info "Seeding $METHODOLOGY/00-methodology.md from the $TYPE playbook"
    render_template "$PLAYBOOK_TEMPLATE" "$M_DIR/00-methodology.md" \
      PROJECT_NAME="$PROJECT_NAME" DATE="$DATE_ISO" METHODOLOGY="$METHODOLOGY" METHODOLOGY_NAME="$M_NAME"
  else
    info "Creating $METHODOLOGY/00-methodology.md (generic — no stock playbook for '$TYPE')"
    render_template "$TEMPLATES_DIR/00-methodology.md.template" "$M_DIR/00-methodology.md" \
      PROJECT_NAME="$PROJECT_NAME" DATE="$DATE_ISO" METHODOLOGY="$METHODOLOGY" METHODOLOGY_NAME="$M_NAME"
  fi
fi

if [[ ! -f "$M_DIR/00-changelog.md" ]]; then
  info "Creating $METHODOLOGY/00-changelog.md"
  render_template "$TEMPLATES_DIR/00-changelog.md.template" "$M_DIR/00-changelog.md" \
    DATE="$DATE_ISO" METHODOLOGY="$METHODOLOGY" METHODOLOGY_NAME="$M_NAME"
fi

# The dated run folder.
mkdir -p "$RUN_DIR"
render_template "$TEMPLATES_DIR/index.md.template" "$RUN_DIR/index.md" \
  METHODOLOGY="$METHODOLOGY" METHODOLOGY_NAME="$M_NAME" SLUG="$SLUG" DATE="$DATE_ISO"
render_template "$TEMPLATES_DIR/findings.md.template" "$RUN_DIR/findings.md" \
  METHODOLOGY="$METHODOLOGY" METHODOLOGY_NAME="$M_NAME" SLUG="$SLUG" DATE="$DATE_ISO"

# Regenerate the audits run-level roll-up (00-index.md) so the new run appears.
# Best-effort: a missing reindexer never blocks scaffolding.
REINDEX="$(dirname "${BASH_SOURCE[0]}")/reindex-audits.sh"
[[ -x "$REINDEX" ]] && bash "$REINDEX" >/dev/null 2>&1 || true

ok "Audit scaffolded: $RUN_DIR"
cat >&2 <<EOF

Next steps:
  1. Open the playbook: $M_DIR/00-methodology.md
  2. Edit the run index: $RUN_DIR/index.md (set scope, auditor, context)
  3. As you find issues, add rows to: $M_DIR/00-inventory.md
  4. Reference IDs from: $RUN_DIR/findings.md
  5. When ready to escalate: /aidex-audit escalate <finding-id>
  6. Validate any time: /aidex-audit validate
EOF
