#!/usr/bin/env bash
# migrate-audit.sh — detect audit-like folders in .context/plans/ and propose migration.
# Usage: migrate-audit.sh [project-dir]
#
# This script does heuristic detection. The actual move + INVENTORY seeding is
# meant to be done by the audit-migrator and inventory-seeder subagents via Claude.
# This script prints the candidate list and the invocation hint.

set -euo pipefail
. "$(dirname "$0")/_lib.sh"

if [[ "${1:-}" == "migrate" ]]; then shift; fi

if [[ -n "${1:-}" ]]; then
  ROOT="$(cd "$1" && pwd -P)"
else
  ROOT="$(find_project_root)"
fi

PLANS_DIR="$ROOT/.context/plans"
AUDITS_DIR="$ROOT/.context/audits"

if [[ ! -d "$PLANS_DIR" ]]; then
  warn "No .context/plans/ found at $PLANS_DIR — nothing to migrate"
  exit 0
fi

info "Scanning $PLANS_DIR for audit-like folders..."
printf '\n'

# Heuristic scoring
declare -a STRONG=()
declare -a AMBIGUOUS=()
declare -a PLANS=()

score_folder() {
  local dir="$1"
  local score=0
  local signals=()

  for f in findings.md issues.md observations.md bugs.md; do
    if [[ -f "$dir/$f" ]]; then
      score=$((score+3)); signals+=("has $f"); break
    fi
  done

  for f in methodology.md method.md checklist.md; do
    if [[ -f "$dir/$f" ]]; then
      score=$((score+2)); signals+=("has $f"); break
    fi
  done

  # case-insensitive inventory match
  if compgen -G "$dir/[Ii][Nn][Vv][Ee][Nn][Tt][Oo][Rr][Yy].md" > /dev/null; then
    score=$((score+3)); signals+=("has INVENTORY.md")
  fi

  for f in metrics.md results.md report.md; do
    if [[ -f "$dir/$f" ]]; then
      score=$((score+1)); signals+=("has $f"); break
    fi
  done

  for f in tasks.md todo.md phases.md plan.md; do
    if [[ -f "$dir/$f" ]]; then
      score=$((score-2)); signals+=("has $f (plan signal)"); break
    fi
  done

  # Numbered implementation files with checkboxes
  if compgen -G "$dir/0[1-9]-*.md" > /dev/null; then
    if grep -l '- \[ \]' "$dir"/0[1-9]-*.md 2>/dev/null | head -1 > /dev/null; then
      score=$((score-2)); signals+=("numbered files with checkboxes (plan signal)")
    fi
  fi

  if [[ -d "$dir/modules" ]]; then
    score=$((score+1)); signals+=("has modules/")
  fi

  if [[ -d "$dir/_archive" ]]; then
    score=$((score+1)); signals+=("has _archive/")
  fi

  local name="$(basename "$dir")"
  local lname="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
  case "$lname" in
    *audit*|*review*|*findings*|*assessment*) score=$((score+2)); signals+=("name suggests audit") ;;
  esac
  case "$lname" in
    *implement*|*refactor*|*migrate*|*add-*|*build-*) score=$((score-2)); signals+=("name suggests plan") ;;
  esac

  printf '%d|%s|%s\n' "$score" "$name" "${signals[*]}"
}

for dir in "$PLANS_DIR"/*/; do
  [[ -d "$dir" ]] || continue
  line="$(score_folder "$dir")"
  score="${line%%|*}"
  rest="${line#*|}"
  name="${rest%%|*}"
  signals="${rest#*|}"

  if [[ $score -ge 3 ]]; then
    STRONG+=("$score|$name|$signals")
  elif [[ $score -le -1 ]]; then
    PLANS+=("$score|$name|$signals")
  else
    AMBIGUOUS+=("$score|$name|$signals")
  fi
done

print_group() {
  local label="$1"; shift
  local color="$1"; shift
  local -a items=("$@")
  if [[ ${#items[@]} -eq 0 ]]; then
    printf '%s%s: none%s\n\n' "$C_DIM" "$label" "$C_RESET"
    return
  fi
  printf '%s%s%s (%d):%s\n' "$color" "$C_BOLD" "$label" "${#items[@]}" "$C_RESET"
  local entry score name signals
  for entry in "${items[@]}"; do
    score="${entry%%|*}"; rest="${entry#*|}"
    name="${rest%%|*}"; signals="${rest#*|}"
    printf '  %s[%+d]%s %s\n' "$color" "$score" "$C_RESET" "$name"
    printf '         %s%s%s\n' "$C_DIM" "$signals" "$C_RESET"
  done
  printf '\n'
}

printf '%sResults:%s\n\n' "$C_BOLD" "$C_RESET"
print_group "Strong audit candidates" "$C_GREEN"  "${STRONG[@]+"${STRONG[@]}"}"
print_group "Ambiguous (needs review)" "$C_YELLOW" "${AMBIGUOUS[@]+"${AMBIGUOUS[@]}"}"
print_group "Plans (skip)"             "$C_DIM"    "${PLANS[@]+"${PLANS[@]}"}"

if [[ ${#STRONG[@]} -eq 0 && ${#AMBIGUOUS[@]} -eq 0 ]]; then
  ok "No audit-like folders detected. Migration not needed."
  exit 0
fi

printf '%sNext steps:%s\n' "$C_BOLD" "$C_RESET"
cat <<EOF

  This script only detects candidates. To execute the migration:

  1. Review the candidates above.
  2. For each you accept, move manually:
       mkdir -p $AUDITS_DIR
       git mv .context/plans/<name> .context/audits/<name>
  3. Rename any "issues.md" or similar to "findings.md" inside the moved folder.
  4. If you have many candidates, invoke Claude with the inventory-seeder agent:
       Read ~/.aidex/skills/audit/agents/inventory-seeder.md
       Provide it the list of moved folders; it will generate INVENTORY rows.
  5. Initialize canonical files if missing:
       /audit new custom placeholder  (then delete the placeholder run)
  6. Add a CHANGELOG.md entry recording the migration.
  7. Run /audit validate to check coherence.

  See ~/.aidex/skills/audit/references/05-migration-guide.md for full details.
EOF
