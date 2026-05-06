#!/usr/bin/env bash
set -euo pipefail

# aidex installer
# Manages installation of skills into ~/.aidex/ and ~/.claude/
#
# Usage:
#   install.sh              First-time install (copy + symlinks)
#   install.sh --update     Update existing installation
#   install.sh --uninstall  Remove installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIDEX_DIR="$HOME/.aidex"
CLAUDE_DIR="$HOME/.claude"
MANIFEST="$AIDEX_DIR/.manifest"
VERSION="0.3.0"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  RED='\033[0;31m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  GREEN='' YELLOW='' RED='' BOLD='' NC=''
fi

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

info()  { echo -e "  ${GREEN}[+]${NC} $1"; }
warn()  { echo -e "  ${YELLOW}[!]${NC} $1"; }
error() { echo -e "  ${RED}[-]${NC} $1"; }
header() { echo -e "\n${BOLD}$1${NC}"; }

ask_choice() {
  local prompt="$1"
  local default="$2"
  echo -en "  $prompt [$default]: " >&2
  read -r choice
  echo "${choice:-$default}"
}

# Detect existing non-aidex symlinks in ~/.claude/
EXISTING_SKILLS_COUNT=0
EXISTING_COMMANDS_COUNT=0
EXISTING_DETECTED=false

detect_existing() {
  # Count skill symlinks NOT pointing to ~/.aidex/
  if [ -d "$CLAUDE_DIR/skills" ]; then
    local total_skills non_aidex_skills
    total_skills=$(find "$CLAUDE_DIR/skills" -maxdepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')
    non_aidex_skills=$(
      find "$CLAUDE_DIR/skills" -maxdepth 1 -type l -exec readlink {} \; 2>/dev/null \
        | grep -c "^$AIDEX_DIR/" || true
    )
    EXISTING_SKILLS_COUNT=$((total_skills - non_aidex_skills))
  fi

  # Count command symlinks (aidex doesn't use commands, so all are external)
  if [ -d "$CLAUDE_DIR/commands" ]; then
    EXISTING_COMMANDS_COUNT=$(
      find "$CLAUDE_DIR/commands" -maxdepth 1 -type l 2>/dev/null | wc -l | tr -d ' '
    )
  fi

  if [ "$EXISTING_SKILLS_COUNT" -gt 0 ] || [ "$EXISTING_COMMANDS_COUNT" -gt 0 ]; then
    EXISTING_DETECTED=true
  fi
}

# Collect items from repo that should be installed
collect_repo_items() {
  local items=()

  # Skills (directories)
  for skill_dir in "$SCRIPT_DIR"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    items+=("skills/$(basename "$skill_dir")")
  done

  printf '%s\n' "${items[@]}"
}

# Read manifest into array
read_manifest() {
  if [ -f "$MANIFEST" ]; then
    cat "$MANIFEST"
  fi
}

# Write manifest
write_manifest() {
  local items=("$@")
  printf '%s\n' "${items[@]}" | sort -u > "$MANIFEST"
}

# Check if item is in manifest
in_manifest() {
  local item="$1"
  [ -f "$MANIFEST" ] && grep -qxF "$item" "$MANIFEST"
}

# ─────────────────────────────────────────────
# Copy a single item from repo to ~/.aidex/
# ─────────────────────────────────────────────

copy_item() {
  local item="$1"
  local src="$SCRIPT_DIR/$item"
  local dst="$AIDEX_DIR/$item"

  if [ -d "$src" ]; then
    # Directory: sync contents
    mkdir -p "$dst"
    rsync -a --delete "$src/" "$dst/"
  else
    # File: copy
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
  fi
}

# ─────────────────────────────────────────────
# Create symlink from ~/.aidex/ to ~/.claude/
# ─────────────────────────────────────────────

create_symlink() {
  local item="$1"
  local src="$AIDEX_DIR/$item"
  local dst="$CLAUDE_DIR/$item"

  # Ensure parent directory exists
  mkdir -p "$(dirname "$dst")"

  if [ -L "$dst" ]; then
    local current_target
    current_target=$(readlink "$dst")
    if [ "$current_target" = "$src" ]; then
      return 0  # Already correct
    fi
    warn "$(basename "$dst"): symlink exists → $current_target (skipping)"
    return 1
  fi

  if [ -e "$dst" ]; then
    warn "$(basename "$dst"): already exists (not a symlink, skipping)"
    return 1
  fi

  ln -s "$src" "$dst"
  return 0
}

# Remove symlink from ~/.claude/ that points to ~/.aidex/
remove_symlink() {
  local item="$1"
  local dst="$CLAUDE_DIR/$item"

  if [ -L "$dst" ]; then
    local target
    target=$(readlink "$dst")
    case "$target" in
      "$AIDEX_DIR"*)
        rm "$dst"
        return 0
        ;;
    esac
  fi
  return 1
}

# ─────────────────────────────────────────────
# INSTALL (first time)
# ─────────────────────────────────────────────

do_install() {
  echo -e "${BOLD}aidex installer${NC}"
  echo "Source: $SCRIPT_DIR"
  echo "Target: $AIDEX_DIR → $CLAUDE_DIR"

  if [ -f "$MANIFEST" ]; then
    echo ""
    warn "aidex is already installed. Use --update to update or --uninstall to remove."
    exit 1
  fi

  # Detect existing non-aidex setup
  detect_existing

  if [ "$EXISTING_DETECTED" = true ]; then
    echo ""
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${YELLOW}Existing setup detected${NC}"
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    [ "$EXISTING_SKILLS_COUNT" -gt 0 ] && echo "  Skills:   $EXISTING_SKILLS_COUNT symlinks in ~/.claude/skills/"
    [ "$EXISTING_COMMANDS_COUNT" -gt 0 ] && echo "  Commands: $EXISTING_COMMANDS_COUNT symlinks in ~/.claude/commands/"
    echo ""
    echo "  aidex will install alongside your existing setup."
    echo "  Nothing will be removed."
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    local proceed
    proceed=$(ask_choice "Continue? (Y/n)" "Y")
    if [[ ! "$proceed" =~ ^[Yy]$ ]] && [ -n "$proceed" ]; then
      echo "  Cancelled."
      exit 0
    fi
  fi

  # Ensure directories exist
  mkdir -p "$AIDEX_DIR/skills"
  mkdir -p "$CLAUDE_DIR/skills"

  local items=()
  local installed=0
  local skipped=0

  header "Copying to ~/.aidex/"

  while IFS= read -r item; do
    items+=("$item")
    copy_item "$item"
    info "$item"
    installed=$((installed + 1))
  done < <(collect_repo_items)

  header "Creating symlinks in ~/.claude/"

  for item in "${items[@]}"; do
    if create_symlink "$item"; then
      info "$item"
    else
      skipped=$((skipped + 1))
    fi
  done

  # Bootstrap skill-registry.json if it doesn't exist
  local registry_template="$AIDEX_DIR/skills/aidex/assets/skill-registry.template.json"
  local registry_file="$AIDEX_DIR/skill-registry.json"
  if [ ! -f "$registry_file" ] && [ -f "$registry_template" ]; then
    cp "$registry_template" "$registry_file"
    info "Initialized skill-registry.json"
  fi

  # Ensure scripts in any skill are executable
  for scripts_dir in "$AIDEX_DIR"/skills/*/scripts; do
    [ -d "$scripts_dir" ] || continue
    chmod +x "$scripts_dir"/*.sh 2>/dev/null || true
  done

  # Write manifest and version
  write_manifest "${items[@]}"
  echo "$VERSION" > "$AIDEX_DIR/.version"

  echo ""
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "  ${GREEN}aidex installed successfully${NC} (v$VERSION)"
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Installed: $installed skills"
  [ "$skipped" -gt 0 ] && echo "  Skipped symlinks: $skipped (conflicts)"
  echo ""

  if [ "$EXISTING_DETECTED" = true ]; then
    echo "  Your existing setup continues to work alongside aidex."
    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    echo "  1. Restart Claude Code"
    echo "  2. Ask Claude: /aidex"
    echo "     aidex will scan your full ecosystem (skills, symlinks,"
    echo "     scopes, .context/, CLAUDE.md, MEMORY.md) and suggest"
    echo "     how to organize everything."
  else
    echo -e "  ${BOLD}Next steps:${NC}"
    echo "  1. Restart Claude Code"
    echo "  2. In any project, ask Claude: /aidex"
    echo "     aidex will scan your ecosystem and help you set up"
    echo "     the right structure (skills, .context/, CLAUDE.md)."
  fi

  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ─────────────────────────────────────────────
# UPDATE
# ─────────────────────────────────────────────

do_update() {
  echo -e "${BOLD}aidex updater${NC}"

  if [ ! -f "$MANIFEST" ]; then
    warn "aidex is not installed. Run install.sh first (without flags)."
    exit 1
  fi

  local modified=()
  local new_items=()
  local removed=()
  local unchanged=0

  # Compare repo items against installed
  while IFS= read -r item; do
    local src="$SCRIPT_DIR/$item"
    local dst="$AIDEX_DIR/$item"

    if [ ! -e "$dst" ]; then
      new_items+=("$item")
    elif [ -d "$src" ]; then
      # Compare directory contents
      if ! diff -rq "$src" "$dst" > /dev/null 2>&1; then
        modified+=("$item")
      else
        unchanged=$((unchanged + 1))
      fi
    else
      # Compare file
      if ! diff -q "$src" "$dst" > /dev/null 2>&1; then
        modified+=("$item")
      else
        unchanged=$((unchanged + 1))
      fi
    fi
  done < <(collect_repo_items)

  # Check for items in manifest but no longer in repo (removed upstream)
  while IFS= read -r item; do
    local src="$SCRIPT_DIR/$item"
    if [ ! -e "$src" ]; then
      removed+=("$item")
    fi
  done < <(read_manifest)

  # Report
  header "Changes detected"

  if [ "${#modified[@]}" -eq 0 ] && [ "${#new_items[@]}" -eq 0 ] && [ "${#removed[@]}" -eq 0 ]; then
    info "Everything is up to date ($unchanged items unchanged)"
    exit 0
  fi

  for item in ${modified[@]+"${modified[@]}"}; do
    echo -e "  ${YELLOW}Modified:${NC}  $item"
  done
  for item in ${new_items[@]+"${new_items[@]}"}; do
    echo -e "  ${GREEN}New:${NC}       $item"
  done
  for item in ${removed[@]+"${removed[@]}"}; do
    echo -e "  ${RED}Removed:${NC}   $item (no longer in repo)"
  done
  echo "  Unchanged: $unchanged items"
  echo ""

  # Ask user
  echo "  Options:"
  echo "    [1] Apply all changes (recommended)"
  echo "    [2] Show diff for each modified item, then ask"
  echo "    [3] Cancel"
  echo ""
  local choice
  choice=$(ask_choice "Choice" "1")

  case "$choice" in
    1)
      # Apply all
      for item in ${modified[@]+"${modified[@]}"} ${new_items[@]+"${new_items[@]}"}; do
        copy_item "$item"
        create_symlink "$item" 2>/dev/null || true
        info "Updated: $item"
      done
      for item in ${removed[@]+"${removed[@]}"}; do
        remove_symlink "$item" 2>/dev/null || true
        rm -rf "$AIDEX_DIR/$item"
        info "Removed: $item"
      done
      ;;
    2)
      # Interactive per item
      for item in ${modified[@]+"${modified[@]}"}; do
        header "Diff: $item"
        if [ -d "$SCRIPT_DIR/$item" ]; then
          diff -rq "$SCRIPT_DIR/$item" "$AIDEX_DIR/$item" 2>/dev/null || true
        else
          diff --color=auto "$AIDEX_DIR/$item" "$SCRIPT_DIR/$item" 2>/dev/null || true
        fi
        echo ""
        local apply
        apply=$(ask_choice "Apply this change? (y/n)" "y")
        if [ "$apply" = "y" ]; then
          copy_item "$item"
          create_symlink "$item" 2>/dev/null || true
          info "Updated: $item"
        else
          warn "Skipped: $item"
        fi
      done
      for item in ${new_items[@]+"${new_items[@]}"}; do
        local apply
        apply=$(ask_choice "Install new item: $item? (y/n)" "y")
        if [ "$apply" = "y" ]; then
          copy_item "$item"
          create_symlink "$item" 2>/dev/null || true
          info "Installed: $item"
        fi
      done
      for item in ${removed[@]+"${removed[@]}"}; do
        local apply
        apply=$(ask_choice "Remove $item (no longer in repo)? (y/n)" "y")
        if [ "$apply" = "y" ]; then
          remove_symlink "$item" 2>/dev/null || true
          rm -rf "$AIDEX_DIR/$item"
          info "Removed: $item"
        fi
      done
      ;;
    3)
      echo "  Cancelled."
      exit 0
      ;;
  esac

  # Bootstrap skill-registry.json on upgrade if missing
  local registry_template="$AIDEX_DIR/skills/aidex/assets/skill-registry.template.json"
  local registry_file="$AIDEX_DIR/skill-registry.json"
  if [ ! -f "$registry_file" ] && [ -f "$registry_template" ]; then
    cp "$registry_template" "$registry_file"
    info "Initialized skill-registry.json"
  fi

  # Ensure scripts in any skill are executable
  for scripts_dir in "$AIDEX_DIR"/skills/*/scripts; do
    [ -d "$scripts_dir" ] || continue
    chmod +x "$scripts_dir"/*.sh 2>/dev/null || true
  done

  # Update manifest
  local all_items=()
  while IFS= read -r item; do
    all_items+=("$item")
  done < <(collect_repo_items)
  write_manifest "${all_items[@]}"

  # Update version
  echo "$VERSION" > "$AIDEX_DIR/.version"

  header "Done"
  echo "  Updated to v$VERSION"
  echo "  Restart Claude Code to load changes."
}

# ─────────────────────────────────────────────
# UNINSTALL
# ─────────────────────────────────────────────

do_uninstall() {
  echo -e "${BOLD}aidex uninstaller${NC}"

  if [ ! -f "$MANIFEST" ]; then
    warn "No manifest found. aidex may not be installed."
    echo ""
  fi

  echo ""
  echo "  What would you like to remove?"
  echo ""
  echo "    [1] Symlinks only (from ~/.claude/) — keeps ~/.aidex/ intact"
  echo "    [2] Symlinks + aidex-managed files (keeps your personal files in ~/.aidex/)"
  echo "    [3] Everything in ~/.aidex/ (complete removal)"
  echo "    [4] Cancel"
  echo ""
  local choice
  choice=$(ask_choice "Choice" "1")

  local removed=0

  case "$choice" in
    1)
      # Remove symlinks only
      header "Removing symlinks from ~/.claude/"
      while IFS= read -r item; do
        if remove_symlink "$item"; then
          info "$item"
          removed=$((removed + 1))
        fi
      done < <(read_manifest)
      rm -f "$MANIFEST" "$AIDEX_DIR/.version"
      ;;
    2)
      # Remove symlinks + aidex files
      header "Removing symlinks from ~/.claude/"
      while IFS= read -r item; do
        if remove_symlink "$item"; then
          info "symlink: $item"
          removed=$((removed + 1))
        fi
      done < <(read_manifest)

      header "Removing aidex-managed files from ~/.aidex/"
      while IFS= read -r item; do
        local dst="$AIDEX_DIR/$item"
        if [ -e "$dst" ]; then
          rm -rf "$dst"
          info "$item"
          removed=$((removed + 1))
        fi
      done < <(read_manifest)
      rm -f "$MANIFEST"

      # Check if anything personal remains
      local remaining
      remaining=$(find "$AIDEX_DIR" -mindepth 1 -not -name '.manifest' 2>/dev/null | head -5)
      if [ -n "$remaining" ]; then
        echo ""
        info "Personal files remain in ~/.aidex/ (not touched)"
      fi
      ;;
    3)
      # Full removal
      header "Removing symlinks from ~/.claude/"
      while IFS= read -r item; do
        if remove_symlink "$item"; then
          info "symlink: $item"
          removed=$((removed + 1))
        fi
      done < <(read_manifest)

      header "Removing ~/.aidex/ entirely"
      echo ""
      local confirm
      confirm=$(ask_choice "Are you sure? This deletes ALL of ~/.aidex/ including personal files (y/n)" "n")
      if [ "$confirm" = "y" ]; then
        rm -rf "$AIDEX_DIR"
        info "Removed ~/.aidex/"
      else
        warn "Cancelled full removal. Only symlinks were removed."
      fi
      ;;
    4)
      echo "  Cancelled."
      exit 0
      ;;
  esac

  header "Done"
  echo "  Removed: $removed items"
  echo "  Restart Claude Code to apply changes."
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

case "${1:-}" in
  --update)
    do_update
    ;;
  --uninstall)
    do_uninstall
    ;;
  --help|-h)
    echo "Usage: install.sh [--update | --uninstall | --help]"
    echo ""
    echo "  (no flags)    First-time install: copy to ~/.aidex/, symlink to ~/.claude/"
    echo "  --update      Update existing installation from repo"
    echo "  --uninstall   Remove installation (interactive)"
    echo "  --help        Show this help"
    ;;
  "")
    do_install
    ;;
  *)
    echo "Unknown option: $1"
    echo "Run install.sh --help for usage."
    exit 1
    ;;
esac
