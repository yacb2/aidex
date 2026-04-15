#!/usr/bin/env bash
# new-audit.sh — scaffold a new audit run.
# Usage: new-audit.sh <type> <slug>
#   <type>: one of ux-audit, ia-opportunities, retest, security-audit, perf-audit, a11y-audit, custom
#   <slug>: kebab-case identifier, e.g. "login-redesign"

set -euo pipefail
. "$(dirname "$0")/_lib.sh"

# Strip leading "new" if the skill dispatcher passed full args
if [[ "${1:-}" == "new" ]]; then shift; fi

if [[ $# -lt 2 ]]; then
  cat <<EOF >&2
Usage: /audit new <type> <slug>

Types:
  ux-audit, ia-opportunities, retest, security-audit, perf-audit, a11y-audit, custom

Example:
  /audit new ux login-redesign
EOF
  exit 2
fi

TYPE_INPUT="$1"
SLUG="$2"

TYPE="$(normalize_type "$TYPE_INPUT")" || die "unknown type: $TYPE_INPUT (valid: ux, ia, retest, security, perf, a11y, custom — or full -audit names)"
is_valid_slug "$SLUG" || die "invalid slug: $SLUG (use kebab-case: lowercase letters, digits, hyphens)"

ROOT="$(find_project_root)"
AUDITS_DIR="$ROOT/.context/audits"
DATE="$(today)"
DATE_ISO="$(today_iso)"
RUN_DIR="$AUDITS_DIR/$DATE-$SLUG"
PROJECT_NAME="$(basename "$ROOT")"

# Ensure top-level structure
mkdir -p "$AUDITS_DIR/methodology"

# Bootstrap canonical files if missing
if [[ ! -f "$AUDITS_DIR/INVENTORY.md" ]]; then
  info "Creating INVENTORY.md"
  render_template "$TEMPLATES_DIR/INVENTORY.md.template" "$AUDITS_DIR/INVENTORY.md" \
    PROJECT_NAME="$PROJECT_NAME" DATE="$DATE_ISO"
fi

if [[ ! -f "$AUDITS_DIR/METHODOLOGY.md" ]]; then
  info "Creating METHODOLOGY.md"
  render_template "$TEMPLATES_DIR/METHODOLOGY.md.template" "$AUDITS_DIR/METHODOLOGY.md" \
    PROJECT_NAME="$PROJECT_NAME" DATE="$DATE_ISO"
fi

if [[ ! -f "$AUDITS_DIR/CHANGELOG.md" ]]; then
  info "Creating CHANGELOG.md"
  render_template "$TEMPLATES_DIR/CHANGELOG.md.template" "$AUDITS_DIR/CHANGELOG.md" \
    DATE="$DATE_ISO"
fi

# Playbook for this type (skip for 'custom' — user writes their own)
if [[ "$TYPE" != "custom" ]]; then
  PLAYBOOK="$AUDITS_DIR/methodology/$TYPE.md"
  PLAYBOOK_TEMPLATE="$TEMPLATES_DIR/methodology/$TYPE.md.template"
  if [[ ! -f "$PLAYBOOK" ]]; then
    if [[ -f "$PLAYBOOK_TEMPLATE" ]]; then
      info "Materializing playbook methodology/$TYPE.md"
      render_template "$PLAYBOOK_TEMPLATE" "$PLAYBOOK" \
        PROJECT_NAME="$PROJECT_NAME" DATE="$DATE_ISO"
    else
      warn "No template found for type $TYPE — playbook file not created"
    fi
  fi
fi

# Create the run folder
if [[ -e "$RUN_DIR" ]]; then
  die "audit run already exists: $RUN_DIR"
fi
mkdir -p "$RUN_DIR"

render_template "$TEMPLATES_DIR/index.md.template" "$RUN_DIR/index.md" \
  AUDIT_TYPE="$TYPE" SLUG="$SLUG" DATE="$DATE_ISO"

render_template "$TEMPLATES_DIR/findings.md.template" "$RUN_DIR/findings.md" \
  SLUG="$SLUG" DATE="$DATE_ISO"

# For custom type, create a stub methodology file alongside
if [[ "$TYPE" == "custom" ]]; then
  CUSTOM_PLAYBOOK="$AUDITS_DIR/methodology/$SLUG.md"
  if [[ ! -f "$CUSTOM_PLAYBOOK" ]]; then
    cat > "$CUSTOM_PLAYBOOK" <<EOF
# Custom Playbook — $SLUG

<!-- Fill in the six standard sections. See ~/.aidex/skills/audit/references/04-playbooks.md for structure. -->

## When to run

## Preparation

## Check matrix / checklist

## Recording findings

## Output artifacts

## Tips
EOF
    info "Created stub methodology/$SLUG.md (custom type — fill in)"
  fi
fi

ok "Audit scaffolded: $RUN_DIR"
cat >&2 <<EOF

Next steps:
  1. Open the playbook: $AUDITS_DIR/methodology/$TYPE.md
  2. Edit the run index: $RUN_DIR/index.md (set scope, auditor, context)
  3. As you find issues, add rows to: $AUDITS_DIR/INVENTORY.md
  4. Reference IDs from: $RUN_DIR/findings.md
  5. When ready to escalate: /audit escalate <finding-id>
  6. Validate any time: /audit validate
EOF
