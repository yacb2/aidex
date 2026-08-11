#!/usr/bin/env bash
# migrate-audit.sh — two migration surfaces:
#
#   (default)  detect audit-like folders in .context/plans/ and propose moving
#              them (heuristic detection; the move + INVENTORY seeding is done
#              by the audit-migrator / inventory-seeder subagents via Claude).
#
#   --layout   convert a LEGACY audits tree to the canon model (rebuild
#              2026-07-02): YYYYMMDD run folders -> YYYY-MM-DD, legacy status
#              values -> base vocabulary (triaged->open, escalated/closed->done,
#              in-progress->doing), YYYYMMDD dates in inventory cells -> ISO,
#              and — with --methodology <name> — root boards + root runs moved
#              under audits/<name>/. Dry-run by default; --apply executes;
#              idempotent (a second --apply is a no-op).
#
# Usage: migrate-audit.sh [project-dir]
#        migrate-audit.sh --layout [--methodology <name>] [--apply] [project-dir]

set -euo pipefail
. "$(dirname "$0")/_lib.sh"

if [[ "${1:-}" == "migrate" ]]; then shift; fi

LAYOUT=0 APPLY=0 METH=""
POSITIONAL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --layout) LAYOUT=1; shift ;;
    --apply) APPLY=1; shift ;;
    --methodology) METH="$2"; shift 2 ;;
    -*) die "unknown flag: $1" ;;
    *) POSITIONAL="$1"; shift ;;
  esac
done

if [[ -n "$POSITIONAL" ]]; then
  ROOT="$(cd "$POSITIONAL" && pwd -P)"
else
  ROOT="$(find_project_root)"
fi

# ---------- --layout: legacy audits tree -> canon ----------
if [[ "$LAYOUT" -eq 1 ]]; then
  AUDITS_DIR="$ROOT/.context/audits"
  [[ -d "$AUDITS_DIR" ]] || die "no audits directory at $AUDITS_DIR"
  changes=0

  act() {  # $1 = description; runs "$@" (from $2) only under --apply
    local desc="$1"; shift
    changes=$((changes+1))
    if [[ "$APPLY" -eq 1 ]]; then
      "$@"
      ok "APPLIED: $desc"
    else
      log "WOULD: $desc"
    fi
  }

  iso_name() {  # 20260610-foo -> 2026-06-10-foo
    printf '%s' "$1" | sed -E 's/^(20[0-9]{2})([0-9]{2})([0-9]{2})-/\1-\2-\3-/'
  }

  iso_dates() {  # stdin filter: bare YYYYMMDD words -> YYYY-MM-DD (BSD sed has no \b; prefer perl)
    if command -v perl >/dev/null 2>&1; then
      perl -pe 's/\b(20\d{2})(\d{2})(\d{2})\b/$1-$2-$3/g'
    else
      sed -E -e 's/(^|[^0-9-])(20[0-9]{2})([0-9]{2})([0-9]{2})($|[^0-9])/\1\2-\3-\4\5/g' \
             -e 's/(^|[^0-9-])(20[0-9]{2})([0-9]{2})([0-9]{2})($|[^0-9])/\1\2-\3-\4\5/g'
    fi
  }

  # Normalize one inventory: legacy status cells -> base vocab; YYYYMMDD -> ISO.
  normalize_inventory() {
    local inv="$1" tmp
    tmp="$(mktemp)"
    awk -F'|' '
      {
        if ($0 ~ /^\|/ && NF >= 11) {
          s = $6; gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
          mapped = s
          if (s == "triaged") mapped = "open"
          else if (s == "escalated" || s == "closed") mapped = "done"
          else if (s == "in-progress") mapped = "doing"
          if (mapped != s) $6 = " " mapped " "
          out = $1
          for (i = 2; i <= NF; i++) out = out "|" $i
          print out
        } else {
          print $0
        }
      }' OFS='' "$inv" | iso_dates > "$tmp"
    if ! cmp -s "$tmp" "$inv"; then
      if [[ "$APPLY" -eq 1 ]]; then mv "$tmp" "$inv"; ok "APPLIED: normalized statuses/dates in ${inv#"$ROOT"/}"
      else rm -f "$tmp"; log "WOULD: normalize legacy statuses/dates in ${inv#"$ROOT"/}"; fi
      changes=$((changes+1))
    else
      rm -f "$tmp"
    fi
  }

  # 1. Root boards -> methodology folder (needs --methodology; a human choice).
  has_root_boards=0
  for b in 00-inventory.md 00-methodology.md 00-changelog.md INVENTORY.md METHODOLOGY.md CHANGELOG.md; do
    [[ -f "$AUDITS_DIR/$b" ]] && has_root_boards=1
  done
  if [[ "$has_root_boards" -eq 1 ]]; then
    if [[ -z "$METH" ]]; then
      warn "root boards found but no --methodology <name> given — boards/runs stay in place (pass --methodology to group them; the slug is a human choice)"
    else
      is_valid_slug "$METH" || die "invalid methodology slug: $METH"
      act "create methodology folder audits/$METH/" mkdir -p "$AUDITS_DIR/$METH"
      for pair in "00-inventory.md|INVENTORY.md" "00-methodology.md|METHODOLOGY.md" "00-changelog.md|CHANGELOG.md"; do
        modern="${pair%%|*}"; legacy="${pair#*|}"
        src=""
        [[ -f "$AUDITS_DIR/$modern" ]] && src="$AUDITS_DIR/$modern"
        [[ -z "$src" && -f "$AUDITS_DIR/$legacy" ]] && src="$AUDITS_DIR/$legacy"
        [[ -n "$src" ]] && act "move $(basename "$src") -> audits/$METH/$modern" mv "$src" "$AUDITS_DIR/$METH/$modern"
      done
    fi
  fi

  # 2. Dated run folders: rename YYYYMMDD -> ISO; move root runs under the
  #    methodology when boards were grouped.
  for run in "$AUDITS_DIR"/[0-9]*-*/ "$AUDITS_DIR"/*/[0-9]*-*/; do
    [[ -d "$run" ]] || continue
    run="${run%/}"
    base="$(basename "$run")"
    parent="$(dirname "$run")"
    case "$parent" in */_archive) continue ;; esac
    new_base="$base"
    [[ "$base" =~ ^[0-9]{8}- ]] && new_base="$(iso_name "$base")"
    dest_parent="$parent"
    if [[ "$parent" == "$AUDITS_DIR" && "$has_root_boards" -eq 1 && -n "$METH" ]]; then
      dest_parent="$AUDITS_DIR/$METH"
    fi
    if [[ "$dest_parent/$new_base" != "$run" ]]; then
      [[ "$APPLY" -eq 1 ]] && mkdir -p "$dest_parent"
      act "move run $base -> ${dest_parent#"$AUDITS_DIR"/}/$new_base" mv "$run" "$dest_parent/$new_base"
    fi
  done

  # 3. Normalize every inventory (methodology folders + any still at root).
  for inv in "$AUDITS_DIR"/00-inventory.md "$AUDITS_DIR"/INVENTORY.md "$AUDITS_DIR"/*/00-inventory.md; do
    [[ -f "$inv" ]] && normalize_inventory "$inv"
  done

  if [[ "$changes" -eq 0 ]]; then
    ok "audits tree already canon — nothing to migrate"
  elif [[ "$APPLY" -eq 0 ]]; then
    log ""
    log "$changes change(s) planned. Re-run with --apply to execute."
  else
    REINDEX="$(dirname "${BASH_SOURCE[0]}")/reindex-audits.sh"
    [[ -x "$REINDEX" ]] && bash "$REINDEX" >/dev/null 2>&1 || true
    ok "layout migration applied ($changes change(s)). Run /aidex-audit validate."
  fi
  exit 0
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
  2. Scaffold the target methodology if it does not exist yet:
       /aidex-audit new <type> <slug>   (creates the methodology folder and its
       three boards: 00-inventory.md, 00-methodology.md, 00-changelog.md; delete
       the scaffolded run if you only wanted the boards). Never create the
       directory by hand -- an empty one is three missing-board violations.
  3. For each candidate you accept, move it into that methodology, ISO-dated:
       git mv .context/plans/<name> .context/audits/<methodology>/YYYY-MM-DD-<slug>
  4. Rename any "issues.md" or similar to "findings.md" inside the moved folder.
  5. If you have many candidates, invoke Claude with the inventory-seeder agent:
       Read ~/.aidex/skills/aidex-audit/agents/inventory-seeder.md
       Provide it the methodology and the list of moved folders; it will generate
       rows for audits/<methodology>/00-inventory.md.
  6. Add an entry to .context/audits/<methodology>/00-changelog.md recording the
     migration.
  7. Refresh the run-level roll-up, which a manual move does not touch:
       bash ~/.aidex/skills/aidex-audit/scripts/reindex-audits.sh
  8. Run /aidex-audit validate to check coherence.

  See ~/.aidex/skills/aidex-audit/references/05-migration-guide.md for full details.
EOF
