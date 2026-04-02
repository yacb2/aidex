#!/usr/bin/env bash
set -euo pipefail

# aidex skill registry manager
# Programmatic JSON manipulation via jq — used by agents and humans alike.
#
# Usage: registry.sh <subcommand> [options]
# Run registry.sh --help for full usage.

AIDEX_DIR="${AIDEX_DIR:-$HOME/.aidex}"
REGISTRY_FILE="${REGISTRY_FILE:-$AIDEX_DIR/skill-registry.json}"
TEMPLATE_FILE="$AIDEX_DIR/skills/aidex/assets/skill-registry.template.json"
TODAY=$(date +%Y-%m-%d)

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

die() { echo "error: $1" >&2; exit 1; }

require_registry() {
  [ -f "$REGISTRY_FILE" ] || die "Registry not found at $REGISTRY_FILE. Run: registry.sh init"
}

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required but not installed"
}

# Atomic write: apply jq filter and replace file
jq_write() {
  local filter="$1"
  shift
  local tmp
  tmp=$(mktemp)
  if jq "$filter" "$@" "$REGISTRY_FILE" > "$tmp"; then
    mv "$tmp" "$REGISTRY_FILE"
  else
    rm -f "$tmp"
    die "jq failed applying filter"
  fi
}

# Split comma-separated string into JSON array
csv_to_json_array() {
  local csv="$1"
  echo "$csv" | tr ',' '\n' | jq -R . | jq -s .
}

# ─────────────────────────────────────────────
# INIT
# ─────────────────────────────────────────────

cmd_init() {
  if [ -f "$REGISTRY_FILE" ]; then
    echo "Registry already exists at $REGISTRY_FILE"
    exit 2
  fi
  if [ -f "$TEMPLATE_FILE" ]; then
    cp "$TEMPLATE_FILE" "$REGISTRY_FILE"
  else
    cat > "$REGISTRY_FILE" <<'EOF'
{
  "version": "2.0",
  "lastScanned": null,
  "stacks": {},
  "skills": {},
  "projects": {}
}
EOF
  fi
  echo "Initialized registry at $REGISTRY_FILE"
}

# ─────────────────────────────────────────────
# SHOW
# ─────────────────────────────────────────────

cmd_show() {
  require_registry
  local section="${1:-}"
  local name="${2:-}"

  case "$section" in
    "")
      jq . "$REGISTRY_FILE"
      ;;
    skills)
      if [ -n "$name" ]; then
        jq --arg n "$name" '.skills[$n] // empty' "$REGISTRY_FILE"
      else
        jq -r '.skills | keys[]' "$REGISTRY_FILE"
      fi
      ;;
    skill)
      [ -n "$name" ] || die "Usage: registry.sh show skill <name>"
      jq --arg n "$name" '.skills[$n] // empty' "$REGISTRY_FILE"
      ;;
    stacks)
      if [ -n "$name" ]; then
        jq --arg n "$name" '.stacks[$n] // empty' "$REGISTRY_FILE"
      else
        jq -r '.stacks | keys[]' "$REGISTRY_FILE"
      fi
      ;;
    stack)
      [ -n "$name" ] || die "Usage: registry.sh show stack <name>"
      jq --arg n "$name" '.stacks[$n] // empty' "$REGISTRY_FILE"
      ;;
    projects)
      if [ -n "$name" ]; then
        jq --arg n "$name" '.projects[$n] // empty' "$REGISTRY_FILE"
      else
        jq -r '.projects | keys[]' "$REGISTRY_FILE"
      fi
      ;;
    project)
      [ -n "$name" ] || die "Usage: registry.sh show project <name>"
      jq --arg n "$name" '.projects[$n] // empty' "$REGISTRY_FILE"
      ;;
    summary)
      jq '{
        skills: (.skills | length),
        stacks: (.stacks | length),
        projects: (.projects | length),
        lastScanned: .lastScanned
      }' "$REGISTRY_FILE"
      ;;
    *)
      die "Unknown section: $section. Use: skills, stacks, projects, summary"
      ;;
  esac
}

# ─────────────────────────────────────────────
# ADD-SKILL
# ─────────────────────────────────────────────

cmd_add_skill() {
  require_registry
  local name="${1:-}"
  [ -n "$name" ] || die "Usage: registry.sh add-skill <name> --category <cat> --tags <t1,t2> --scope <scope>"
  shift

  local category="" tags="" scope="" library_path=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --category)   category="$2"; shift 2 ;;
      --tags)       tags="$2"; shift 2 ;;
      --scope)      scope="$2"; shift 2 ;;
      --library-path) library_path="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  [ -n "$category" ] || die "--category is required"
  [ -n "$scope" ] || die "--scope is required"

  local tags_json
  if [ -n "$tags" ]; then
    tags_json=$(csv_to_json_array "$tags")
  else
    tags_json="[]"
  fi

  local base_filter
  base_filter=$(cat <<FILTER
.skills[\$name] = {
  category: \$category,
  tags: ($tags_json),
  scope: \$scope,
  lastUpdated: \$today,
  usedBy: (if .skills[\$name].usedBy then .skills[\$name].usedBy else [] end),
  localOverrides: (if .skills[\$name].localOverrides then .skills[\$name].localOverrides else [] end),
  symlinkedBy: (if .skills[\$name].symlinkedBy then .skills[\$name].symlinkedBy else [] end)
}
FILTER
)

  if [ -n "$library_path" ]; then
    base_filter="$base_filter | .skills[\$name].libraryPath = \$lpath"
    jq_write "$base_filter" \
      --arg name "$name" \
      --arg category "$category" \
      --arg scope "$scope" \
      --arg today "$TODAY" \
      --arg lpath "$library_path"
  else
    jq_write "$base_filter" \
      --arg name "$name" \
      --arg category "$category" \
      --arg scope "$scope" \
      --arg today "$TODAY"
  fi

  echo "Added skill: $name"
}

# ─────────────────────────────────────────────
# UPDATE-SKILL
# ─────────────────────────────────────────────

cmd_update_skill() {
  require_registry
  local name="${1:-}"
  [ -n "$name" ] || die "Usage: registry.sh update-skill <name> [options]"
  shift

  # Verify skill exists
  local exists
  exists=$(jq --arg n "$name" '.skills | has($n)' "$REGISTRY_FILE")
  [ "$exists" = "true" ] || die "Skill '$name' not found in registry"

  while [ $# -gt 0 ]; do
    case "$1" in
      --category)
        jq_write '.skills[$n].category = $v | .skills[$n].lastUpdated = $today' \
          --arg n "$name" --arg v "$2" --arg today "$TODAY"
        shift 2 ;;
      --tags)
        local tags_json
        tags_json=$(csv_to_json_array "$2")
        jq_write ".skills[\$n].tags = $tags_json | .skills[\$n].lastUpdated = \$today" \
          --arg n "$name" --arg today "$TODAY"
        shift 2 ;;
      --scope)
        jq_write '.skills[$n].scope = $v | .skills[$n].lastUpdated = $today' \
          --arg n "$name" --arg v "$2" --arg today "$TODAY"
        shift 2 ;;
      --library-path)
        jq_write '.skills[$n].libraryPath = $v | .skills[$n].lastUpdated = $today' \
          --arg n "$name" --arg v "$2" --arg today "$TODAY"
        shift 2 ;;
      --add-used-by)
        jq_write 'if (.skills[$n].usedBy | index($v)) then . else .skills[$n].usedBy += [$v] end' \
          --arg n "$name" --arg v "$2"
        shift 2 ;;
      --remove-used-by)
        jq_write '.skills[$n].usedBy = (.skills[$n].usedBy | map(select(. != $v)))' \
          --arg n "$name" --arg v "$2"
        shift 2 ;;
      --add-local-override)
        jq_write 'if (.skills[$n].localOverrides | index($v)) then . else .skills[$n].localOverrides += [$v] end' \
          --arg n "$name" --arg v "$2"
        shift 2 ;;
      --remove-local-override)
        jq_write '.skills[$n].localOverrides = (.skills[$n].localOverrides | map(select(. != $v)))' \
          --arg n "$name" --arg v "$2"
        shift 2 ;;
      --add-symlinked-by)
        jq_write 'if (.skills[$n].symlinkedBy | index($v)) then . else .skills[$n].symlinkedBy += [$v] end' \
          --arg n "$name" --arg v "$2"
        shift 2 ;;
      --remove-symlinked-by)
        jq_write '.skills[$n].symlinkedBy = (.skills[$n].symlinkedBy | map(select(. != $v)))' \
          --arg n "$name" --arg v "$2"
        shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  echo "Updated skill: $name"
}

# ─────────────────────────────────────────────
# REMOVE-SKILL
# ─────────────────────────────────────────────

cmd_remove_skill() {
  require_registry
  local name="${1:-}"
  [ -n "$name" ] || die "Usage: registry.sh remove-skill <name>"

  jq_write 'del(.skills[$n])' --arg n "$name"
  echo "Removed skill: $name"
}

# ─────────────────────────────────────────────
# SET-STACK
# ─────────────────────────────────────────────

cmd_set_stack() {
  require_registry
  local id="${1:-}"
  [ -n "$id" ] || die "Usage: registry.sh set-stack <id> --label <label> --detect <json> --skills <s1,s2>"
  shift

  local label="" detect="" skills=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --label)   label="$2"; shift 2 ;;
      --detect)  detect="$2"; shift 2 ;;
      --skills)  skills="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  [ -n "$label" ] || die "--label is required"
  [ -n "$skills" ] || die "--skills is required"

  local skills_json
  skills_json=$(csv_to_json_array "$skills")

  if [ -n "$detect" ]; then
    # detect is a JSON object string like '{"pyproject.toml":"django"}'
    jq_write ".stacks[\$id] = {label: \$label, detect: ($detect), skills: ($skills_json)}" \
      --arg id "$id" --arg label "$label"
  else
    jq_write ".stacks[\$id] = {label: \$label, detect: {}, skills: ($skills_json)}" \
      --arg id "$id" --arg label "$label"
  fi

  echo "Set stack: $id"
}

# ─────────────────────────────────────────────
# REMOVE-STACK
# ─────────────────────────────────────────────

cmd_remove_stack() {
  require_registry
  local id="${1:-}"
  [ -n "$id" ] || die "Usage: registry.sh remove-stack <id>"

  jq_write 'del(.stacks[$n])' --arg n "$id"
  echo "Removed stack: $id"
}

# ─────────────────────────────────────────────
# ADD-PROJECT
# ─────────────────────────────────────────────

cmd_add_project() {
  require_registry
  local id="${1:-}"
  [ -n "$id" ] || die "Usage: registry.sh add-project <id> --path <path>"
  shift

  local path="" stacks="" local_skills="" symlinked_skills=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --path)              path="$2"; shift 2 ;;
      --stacks)            stacks="$2"; shift 2 ;;
      --local-skills)      local_skills="$2"; shift 2 ;;
      --symlinked-skills)  symlinked_skills="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  [ -n "$path" ] || die "--path is required"

  local stacks_json local_json symlinked_json
  stacks_json=$([ -n "$stacks" ] && csv_to_json_array "$stacks" || echo "[]")
  local_json=$([ -n "$local_skills" ] && csv_to_json_array "$local_skills" || echo "[]")
  symlinked_json=$([ -n "$symlinked_skills" ] && csv_to_json_array "$symlinked_skills" || echo "[]")

  jq_write ".projects[\$id] = {
    path: \$path,
    stacks: ($stacks_json),
    localSkills: ($local_json),
    symlinkedSkills: ($symlinked_json),
    lastAudited: null
  }" --arg id "$id" --arg path "$path"

  echo "Added project: $id"
}

# ─────────────────────────────────────────────
# UPDATE-PROJECT
# ─────────────────────────────────────────────

cmd_update_project() {
  require_registry
  local id="${1:-}"
  [ -n "$id" ] || die "Usage: registry.sh update-project <id> [options]"
  shift

  local exists
  exists=$(jq --arg n "$id" '.projects | has($n)' "$REGISTRY_FILE")
  [ "$exists" = "true" ] || die "Project '$id' not found in registry"

  while [ $# -gt 0 ]; do
    case "$1" in
      --stacks)
        local stacks_json
        stacks_json=$(csv_to_json_array "$2")
        jq_write ".projects[\$n].stacks = $stacks_json" --arg n "$id"
        shift 2 ;;
      --add-local-skill)
        jq_write 'if (.projects[$n].localSkills | index($v)) then . else .projects[$n].localSkills += [$v] end' \
          --arg n "$id" --arg v "$2"
        shift 2 ;;
      --remove-local-skill)
        jq_write '.projects[$n].localSkills = (.projects[$n].localSkills | map(select(. != $v)))' \
          --arg n "$id" --arg v "$2"
        shift 2 ;;
      --add-symlinked-skill)
        jq_write 'if (.projects[$n].symlinkedSkills | index($v)) then . else .projects[$n].symlinkedSkills += [$v] end' \
          --arg n "$id" --arg v "$2"
        shift 2 ;;
      --remove-symlinked-skill)
        jq_write '.projects[$n].symlinkedSkills = (.projects[$n].symlinkedSkills | map(select(. != $v)))' \
          --arg n "$id" --arg v "$2"
        shift 2 ;;
      --last-audited)
        jq_write '.projects[$n].lastAudited = $v' --arg n "$id" --arg v "$2"
        shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  echo "Updated project: $id"
}

# ─────────────────────────────────────────────
# REMOVE-PROJECT
# ─────────────────────────────────────────────

cmd_remove_project() {
  require_registry
  local id="${1:-}"
  [ -n "$id" ] || die "Usage: registry.sh remove-project <id>"

  jq_write 'del(.projects[$n])' --arg n "$id"
  echo "Removed project: $id"
}

# ─────────────────────────────────────────────
# SCAN
# ─────────────────────────────────────────────

cmd_scan() {
  require_registry
  local project_dir=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --project-dir) project_dir="$2"; shift 2 ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  local added=0 updated=0

  # Scan shared skills (~/.aidex/skills/)
  if [ -d "$AIDEX_DIR/skills" ]; then
    for skill_dir in "$AIDEX_DIR/skills"/*/; do
      [ -d "$skill_dir" ] || continue
      local name
      name=$(basename "$skill_dir")
      local exists
      exists=$(jq --arg n "$name" '.skills | has($n)' "$REGISTRY_FILE")
      if [ "$exists" = "false" ]; then
        local category
        category=$(detect_category "$skill_dir")
        jq_write '.skills[$n] = {
          category: $cat,
          tags: [],
          scope: "shared",
          lastUpdated: $today,
          usedBy: [],
          localOverrides: [],
          symlinkedBy: []
        }' --arg n "$name" --arg cat "$category" --arg today "$TODAY"
        added=$((added + 1))
      fi
    done
  fi

  # Scan global skills (~/.claude/skills/)
  if [ -d "$HOME/.claude/skills" ]; then
    for entry in "$HOME/.claude/skills"/*/; do
      [ -e "$entry" ] || continue
      local name
      name=$(basename "$entry")
      local exists
      exists=$(jq --arg n "$name" '.skills | has($n)' "$REGISTRY_FILE")

      if [ -L "${entry%/}" ]; then
        local target
        target=$(readlink "${entry%/}")
        # Skip aidex-managed symlinks (already handled above)
        case "$target" in
          "$AIDEX_DIR"*) continue ;;
        esac
        # External symlink — register as global
        if [ "$exists" = "false" ]; then
          local category
          category=$(detect_category "$entry")
          jq_write '.skills[$n] = {
            category: $cat,
            tags: [],
            scope: "global",
            lastUpdated: $today,
            usedBy: [],
            localOverrides: [],
            symlinkedBy: [],
            libraryPath: $lpath
          }' --arg n "$name" --arg cat "$category" --arg today "$TODAY" --arg lpath "$target"
          added=$((added + 1))
        fi
      else
        # Real directory — personal global skill
        if [ "$exists" = "false" ]; then
          local category
          category=$(detect_category "$entry")
          jq_write '.skills[$n] = {
            category: $cat,
            tags: [],
            scope: "global",
            lastUpdated: $today,
            usedBy: [],
            localOverrides: [],
            symlinkedBy: []
          }' --arg n "$name" --arg cat "$category" --arg today "$TODAY"
          added=$((added + 1))
        fi
      fi
    done
  fi

  # Scan project-local skills
  if [ -n "$project_dir" ] && [ -d "$project_dir/.claude/skills" ]; then
    local project_id
    project_id=$(basename "$project_dir")

    # Ensure project exists in registry
    local proj_exists
    proj_exists=$(jq --arg n "$project_id" '.projects | has($n)' "$REGISTRY_FILE")
    if [ "$proj_exists" = "false" ]; then
      jq_write '.projects[$n] = {
        path: $path,
        stacks: [],
        localSkills: [],
        symlinkedSkills: [],
        lastAudited: null
      }' --arg n "$project_id" --arg path "$project_dir"
    fi

    for entry in "$project_dir/.claude/skills"/*/; do
      [ -e "$entry" ] || continue
      local name
      name=$(basename "$entry")

      if [ -L "${entry%/}" ]; then
        # Symlinked skill in project
        jq_write 'if (.projects[$pid].symlinkedSkills | index($sn)) then . else .projects[$pid].symlinkedSkills += [$sn] end' \
          --arg pid "$project_id" --arg sn "$name"
      else
        # Local skill in project
        jq_write 'if (.projects[$pid].localSkills | index($sn)) then . else .projects[$pid].localSkills += [$sn] end' \
          --arg pid "$project_id" --arg sn "$name"
      fi
    done

    # Detect stack
    local detected_stacks
    detected_stacks=$(detect_project_stacks "$project_dir")
    if [ -n "$detected_stacks" ]; then
      local stacks_json
      stacks_json=$(echo "$detected_stacks" | jq -R . | jq -s .)
      jq_write ".projects[\$pid].stacks = $stacks_json" --arg pid "$project_id"
    fi

    # Mark as audited
    jq_write '.projects[$pid].lastAudited = $today' --arg pid "$project_id" --arg today "$TODAY"
  fi

  # Update lastScanned
  jq_write '.lastScanned = $today' --arg today "$TODAY"

  echo "Scan complete. Added: $added skills. Registry: $REGISTRY_FILE"
}

# ─────────────────────────────────────────────
# Stack & category detection helpers
# ─────────────────────────────────────────────

detect_category() {
  local skill_dir="$1"
  local skill_md="$skill_dir/SKILL.md"

  if [ ! -f "$skill_md" ]; then
    echo "unknown"
    return
  fi

  # Simple heuristic from SKILL.md content
  local content
  content=$(head -30 "$skill_md" 2>/dev/null || true)

  case "$content" in
    *frontend*|*vue*|*react*|*svelte*|*component*|*UI*) echo "frontend" ;;
    *backend*|*django*|*flask*|*fastapi*|*API*|*api*) echo "backend" ;;
    *test*|*testing*|*playwright*|*vitest*) echo "testing" ;;
    *design*|*excalidraw*|*canvas*|*brand*|*art*) echo "design" ;;
    *animation*|*gsap*) echo "animation" ;;
    *doc*|*documentation*|*audit*|*skill*|*memory*) echo "devtools" ;;
    *git*|*deploy*|*ci*|*debug*) echo "devtools" ;;
    *file*|*pdf*|*docx*|*xlsx*|*pptx*) echo "fileops" ;;
    *) echo "other" ;;
  esac
}

detect_project_stacks() {
  local project_dir="$1"
  local stacks=""

  # Check multiple common locations for package.json
  # Uses jq has() for exact key match — avoids false positives like "@next/env" matching "next"
  for pkg_path in "$project_dir/package.json" "$project_dir/frontend/package.json"; do
    if [ -f "$pkg_path" ]; then
      local all_deps
      all_deps=$(jq '(.dependencies // {}) + (.devDependencies // {})' "$pkg_path" 2>/dev/null || echo "{}")

      echo "$all_deps" | jq -e 'has("vue")' >/dev/null 2>&1 && stacks="${stacks:+$stacks\n}vue"
      echo "$all_deps" | jq -e 'has("react")' >/dev/null 2>&1 && stacks="${stacks:+$stacks\n}react"
      echo "$all_deps" | jq -e 'has("svelte")' >/dev/null 2>&1 && stacks="${stacks:+$stacks\n}svelte"
      echo "$all_deps" | jq -e 'has("next")' >/dev/null 2>&1 && stacks="${stacks:+$stacks\n}nextjs"
      echo "$all_deps" | jq -e 'has("nuxt")' >/dev/null 2>&1 && stacks="${stacks:+$stacks\n}nuxt"
      echo "$all_deps" | jq -e 'has("@angular/core")' >/dev/null 2>&1 && stacks="${stacks:+$stacks\n}angular"
    fi
  done

  # Check Python
  for py_path in "$project_dir/pyproject.toml" "$project_dir/backend/pyproject.toml" "$project_dir/requirements.txt" "$project_dir/backend/requirements.txt"; do
    if [ -f "$py_path" ]; then
      local content
      content=$(cat "$py_path" 2>/dev/null || true)
      case "$content" in
        *django*|*Django*) stacks="${stacks:+$stacks\n}django" ;;
      esac
      case "$content" in
        *flask*|*Flask*)   stacks="${stacks:+$stacks\n}flask" ;;
      esac
      case "$content" in
        *fastapi*|*FastAPI*) stacks="${stacks:+$stacks\n}fastapi" ;;
      esac
    fi
  done

  # Check other languages
  [ -f "$project_dir/Cargo.toml" ] && stacks="${stacks:+$stacks\n}rust"
  [ -f "$project_dir/go.mod" ] && stacks="${stacks:+$stacks\n}go"
  [ -f "$project_dir/Gemfile" ] && stacks="${stacks:+$stacks\n}ruby"
  [ -f "$project_dir/composer.json" ] && stacks="${stacks:+$stacks\n}php"

  # Deduplicate and output
  if [ -n "$stacks" ]; then
    echo -e "$stacks" | sort -u
  fi
}

# ─────────────────────────────────────────────
# HELP
# ─────────────────────────────────────────────

cmd_help() {
  cat <<'HELP'
aidex skill registry manager

Usage: registry.sh <subcommand> [options]

Subcommands:
  init                                Initialize registry from template
  show [skills|stacks|projects|summary]  Show registry contents
  show skill|stack|project <name>     Show details for one entry

  add-skill <name> --category <cat> --scope <scope> [--tags <t1,t2>] [--library-path <path>]
  update-skill <name> [--category X] [--tags X] [--scope X] [--add-used-by X] [--remove-used-by X]
                      [--add-local-override X] [--add-symlinked-by X] [--library-path X]
  remove-skill <name>

  set-stack <id> --label <label> --skills <s1,s2> [--detect <json>]
  remove-stack <id>

  add-project <id> --path <path> [--stacks X] [--local-skills X] [--symlinked-skills X]
  update-project <id> [--stacks X] [--add-local-skill X] [--add-symlinked-skill X] [--last-audited X]
  remove-project <id>

  scan [--project-dir <path>]         Auto-populate from filesystem

Environment:
  REGISTRY_FILE   Override registry path (default: ~/.aidex/skill-registry.json)
  AIDEX_DIR       Override aidex directory (default: ~/.aidex)

Exit codes:
  0  Success
  1  Error
  2  No-op (already in desired state)
HELP
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

require_jq

case "${1:-}" in
  init)           shift; cmd_init "$@" ;;
  show)           shift; cmd_show "$@" ;;
  add-skill)      shift; cmd_add_skill "$@" ;;
  update-skill)   shift; cmd_update_skill "$@" ;;
  remove-skill)   shift; cmd_remove_skill "$@" ;;
  set-stack)      shift; cmd_set_stack "$@" ;;
  remove-stack)   shift; cmd_remove_stack "$@" ;;
  add-project)    shift; cmd_add_project "$@" ;;
  update-project) shift; cmd_update_project "$@" ;;
  remove-project) shift; cmd_remove_project "$@" ;;
  scan)           shift; cmd_scan "$@" ;;
  --help|-h|help) cmd_help ;;
  "")             cmd_help; exit 1 ;;
  *)              die "Unknown command: $1. Run registry.sh --help" ;;
esac
