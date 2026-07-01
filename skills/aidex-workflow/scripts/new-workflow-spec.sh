#!/usr/bin/env bash
# new-workflow-spec.sh — scaffold a workflow-spec in .context/workflows/.
# Usage: new-workflow-spec.sh new <slug>
#   <slug>: kebab-case identifier, e.g. "review-auth-across-dimensions"
#
# Self-contained: inlines its helpers so it does not depend on a sibling _lib.sh.
# On success, prints the created file path to stdout.

set -euo pipefail

# Resolve the skill dir even via symlink.
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"
TEMPLATES_DIR="$SKILL_DIR/assets/templates"

# Next sequential id WF-NNN across active + _archive (ids stay stable).
next_workflow_id() {
  local dir="$1" max=0 n f
  shopt -s nullglob
  for f in "$dir"/*.md "$dir"/_archive/*.md; do
    [[ -f "$f" ]] || continue
    n="$(awk '/^---[[:space:]]*$/{c++; if(c==2) exit} c==1 && $1 ~ /^id:/ {v=$2; gsub(/[^0-9]/,"",v); print v; exit}' "$f")"
    [[ -n "$n" ]] && (( 10#$n > max )) && max=$((10#$n))
  done
  shopt -u nullglob
  printf 'WF-%03d' $((max+1))
}

# Strip leading "new" dispatched by the skill.
if [[ "${1:-}" == "new" ]]; then shift; fi

SLUG="${1:-}"
if [[ -z "$SLUG" ]]; then
  cat <<EOF >&2
Usage: /aidex-workflow new <slug>

Example:
  /aidex-workflow new review-auth-across-dimensions
EOF
  exit 2
fi
is_valid_slug "$SLUG" || die "invalid slug: $SLUG (use kebab-case: lowercase letters, digits, hyphens)"

ROOT="$(find_project_root)"
WORKFLOWS_DIR="$ROOT/.context/workflows"
DATE_ISO="$(today_iso)"
mkdir -p "$WORKFLOWS_DIR"

ID="$(next_workflow_id "$WORKFLOWS_DIR")"
OUT="$WORKFLOWS_DIR/$DATE_ISO-$SLUG.md"

render_template "$TEMPLATES_DIR/workflow-spec.md.template" "$OUT" \
  ID="$ID" SLUG="$SLUG" DATE="$DATE_ISO"

ok "Workflow-spec scaffolded: $OUT"
cat >&2 <<EOF

Next steps:
  1. Fill the spec: Goal, Shape, Work-list, Per-agent model+effort, Gate policy.
  2. See the shape catalog: $SKILL_DIR/references/01-workflow-spec-conventions.md
  3. When ready: /aidex-workflow run $SLUG
EOF

# Machine-readable path on stdout.
printf '%s\n' "$OUT"
