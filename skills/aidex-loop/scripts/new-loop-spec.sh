#!/usr/bin/env bash
# new-loop-spec.sh — scaffold a loop-spec in .context/loops/.
# Usage: new-loop-spec.sh new <slug>
#   <slug>: kebab-case identifier, e.g. "csv-export-greenfield"
#
# Self-contained: inlines its helpers so it does not depend on a sibling _lib.sh.
# On success, prints the created file path to stdout.

set -euo pipefail

# Resolve the skill dir even via symlink.
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"
TEMPLATES_DIR="$SKILL_DIR/assets/templates"

# Next sequential id LOOP-NNN across active + _archive (ids stay stable).
next_loop_id() {
  local dir="$1" max=0 n f
  shopt -s nullglob
  for f in "$dir"/*.md "$dir"/_archive/*.md; do
    [[ -f "$f" ]] || continue
    n="$(awk '/^---[[:space:]]*$/{c++; if(c==2) exit} c==1 && $1 ~ /^id:/ {v=$2; gsub(/[^0-9]/,"",v); print v; exit}' "$f")"
    [[ -n "$n" ]] && (( 10#$n > max )) && max=$((10#$n))
  done
  shopt -u nullglob
  printf 'LOOP-%03d' $((max+1))
}

# Strip leading "new" dispatched by the skill.
if [[ "${1:-}" == "new" ]]; then shift; fi

SLUG="${1:-}"
if [[ -z "$SLUG" ]]; then
  cat <<EOF >&2
Usage: /aidex-loop new <slug>

Example:
  /aidex-loop new csv-export-greenfield
EOF
  exit 2
fi
is_valid_slug "$SLUG" || die "invalid slug: $SLUG (use kebab-case: lowercase letters, digits, hyphens)"

ROOT="$(find_project_root)"
LOOPS_DIR="$ROOT/.context/loops"
DATE_ISO="$(today_iso)"
mkdir -p "$LOOPS_DIR"

ID="$(next_loop_id "$LOOPS_DIR")"
OUT="$LOOPS_DIR/$DATE_ISO-$SLUG.md"

render_template "$TEMPLATES_DIR/loop-spec.md.template" "$OUT" \
  ID="$ID" SLUG="$SLUG" DATE="$DATE_ISO"

ok "Loop-spec scaffolded: $OUT"
cat >&2 <<EOF

Next steps:
  1. Fill the spec: Goal, Stop condition (gate), Engine + why, Guardrails.
  2. See the engine matrix: $SKILL_DIR/references/01-loop-engines.md
  3. When ready: /aidex-loop run $SLUG
EOF

# Machine-readable path on stdout.
printf '%s\n' "$OUT"
