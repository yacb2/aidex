#!/usr/bin/env bash
set -euo pipefail

# aidex installer
# Installs the suite straight into ~/.claude/ — the tree Claude Code reads —
# as real files, the same way any other skill lands there:
#
#   ~/.claude/skills/<skill>/     one directory per skill (copy)
#   ~/.claude/rules/<rule>.md     always-on rules (copy)
#   ~/.claude/hooks/<hook>.sh     shipped hooks, inert until wired in settings.json
#   ~/.claude/aidex/              install state: manifest, version, commit, backups
#
# Until v0.39 the suite was copied to ~/.aidex/ and symlinked from ~/.claude/.
# That layer was built for a per-project skill mechanism Claude Code did not
# have; it has one now (project .claude/skills, skillOverrides, nested skills),
# and symlinked skills/rules were the path with three separate loader bugs
# (2.0.62, 2.1.198, 2.1.239). The installer migrates an old layout on its own:
# links are replaced by copies, anything of the user's that lived in ~/.aidex/
# is materialised, and the directory is moved aside — never deleted.
#
# Usage:
#   install.sh              First-time install
#   install.sh --update     Update from the repo (also migrates an old layout)
#   install.sh --uninstall  Remove what aidex installed — nothing else
#   install.sh --doctor     Health check, PASS/FAIL, exit 1 on any failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
STATE_DIR="$CLAUDE_DIR/aidex"
MANIFEST="$STATE_DIR/manifest"
# The pre-0.40 layout, read only to migrate away from it.
LEGACY_DIR="${AIDEX_DIR:-$HOME/.aidex}"
VERSION="0.40.0"

# Hooks that install. The others in hooks/ are retired (aidex-router,
# durability-*) and stay in the repo as history with their tests; installing
# them put dead scripts and their eval corpus on every machine.
SHIPPED_HOOKS="${AIDEX_SHIPPED_HOOKS:-context-depth-nudge.sh}"

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

# The commit the installed tree came from. VERSION only moves on a release, so a
# matching version says nothing about the fixes that landed between two of them.
# Empty when the source is not a git checkout (tests build a bare fixture repo).
repo_commit() {
  git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || true
}

# The only writer of the install markers — version and commit move together or
# they can disagree, which is the failure they exist to make visible.
stamp_install() {
  mkdir -p "$STATE_DIR"
  echo "$VERSION" > "$STATE_DIR/version"
  local sha
  sha="$(repo_commit)"
  if [ -n "$sha" ]; then
    echo "$sha" > "$STATE_DIR/commit"
  else
    rm -f "$STATE_DIR/commit"
  fi
}

ask_choice() {
  local prompt="$1"
  local default="$2"
  # Take the default when there is nothing to read, rather than blocking on a
  # prompt nobody can see. The condition is EOF, NOT "stdin is not a tty": a pipe
  # carrying answers is not a terminal either (tests/test-install.sh pipes choices).
  if [[ -n "${AIDEX_ASSUME_DEFAULTS:-}" ]]; then
    echo "$default"
    return 0
  fi
  [[ -t 0 ]] && echo -en "  $prompt [$default]: " >&2
  read -r choice || choice=""
  echo "${choice:-$default}"
}

# Items are repo-relative: skills/<name>, rules/<file>.md, hooks/<file>.sh.
collect_repo_items() {
  local items=()
  for skill_dir in "$SCRIPT_DIR"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    items+=("skills/$(basename "$skill_dir")")
  done
  if [ -d "$SCRIPT_DIR/rules" ]; then
    for rule_file in "$SCRIPT_DIR"/rules/*.md; do
      [ -f "$rule_file" ] || continue
      items+=("rules/$(basename "$rule_file")")
    done
  fi
  local hook
  for hook in $SHIPPED_HOOKS; do
    [ -f "$SCRIPT_DIR/hooks/$hook" ] && items+=("hooks/$hook")
  done
  printf '%s\n' "${items[@]}"
}

# Where an item lives once installed. Same relative path under ~/.claude/.
item_dst() { echo "$CLAUDE_DIR/$1"; }

read_manifest() {
  if [ -f "$MANIFEST" ]; then
    cat "$MANIFEST"
  fi
}

write_manifest() {
  local items=("$@")
  mkdir -p "$STATE_DIR"
  printf '%s\n' "${items[@]}" | sort -u > "$MANIFEST"
}

in_manifest() {
  [ -f "$MANIFEST" ] && grep -qxF "$1" "$MANIFEST"
}

# Whether the path at an item's destination is aidex's to overwrite. Ours: absent,
# listed in the manifest, or a symlink into the legacy ~/.aidex/ (migration).
# Anything else is the user's — a skill of theirs that happens to share a name —
# and the installer must not eat it (BL-* deep audit 2026-07-25: create_symlink
# refused to clobber for the same reason).
dst_is_ours() {
  local item="$1" dst
  dst="$(item_dst "$item")"
  [ -e "$dst" ] || [ -L "$dst" ] || return 0
  in_manifest "$item" && return 0
  if [ -L "$dst" ]; then
    case "$(readlink "$dst")" in "$LEGACY_DIR"/*) return 0 ;; esac
    return 1
  fi
  # Byte-identical to what the repo ships: a by-hand copy of this very item
  # (the depth hook was placed in ~/.claude/hooks/ by hand before it shipped).
  # Adopting it changes no content and puts it under the manifest.
  if [ -d "$dst" ]; then
    diff -rq -x '__pycache__' -x '*.pyc' -x '.DS_Store' "$SCRIPT_DIR/$item" "$dst" >/dev/null 2>&1 && return 0
  else
    diff -q "$SCRIPT_DIR/$item" "$dst" >/dev/null 2>&1 && return 0
  fi
  return 1
}

# Copy one item from the repo to its place under ~/.claude/. A symlink at the
# destination is removed first — copying THROUGH a link into ~/.aidex/ would
# write the old tree instead of replacing it.
copy_item() {
  local item="$1"
  local src="$SCRIPT_DIR/$item"
  local dst
  dst="$(item_dst "$item")"
  [ -L "$dst" ] && rm "$dst"
  if [ -d "$src" ]; then
    # Exclude gitignored build junk — copying __pycache__/*.pyc from a working
    # tree causes perpetual "Modified" churn.
    mkdir -p "$dst"
    rsync -a --delete \
      --exclude='__pycache__/' --exclude='*.pyc' --exclude='.DS_Store' \
      "$src/" "$dst/"
  else
    mkdir -p "$(dirname "$dst")"
    cp -f "$src" "$dst"
  fi
}

remove_item() {
  local dst
  dst="$(item_dst "$1")"
  if [ -L "$dst" ]; then
    rm "$dst"
  elif [ -e "$dst" ]; then
    rm -rf "$dst"
  fi
}

# Execute bits do not survive every copy path; apply them after any install/update.
fix_exec_bits() {
  local d
  for d in "$CLAUDE_DIR"/skills/*/scripts; do
    [ -d "$d" ] || continue
    in_manifest "skills/$(basename "$(dirname "$d")")" || continue
    chmod +x "$d"/*.sh 2>/dev/null || true
  done
  local hook
  for hook in $SHIPPED_HOOKS; do
    [ -f "$CLAUDE_DIR/hooks/$hook" ] && chmod +x "$CLAUDE_DIR/hooks/$hook"
  done
  return 0
}

# ─────────────────────────────────────────────
# Migration from the pre-0.40 layout (~/.aidex/ + symlinks)
# ─────────────────────────────────────────────

legacy_present() { [ -d "$LEGACY_DIR" ]; }

# Runs before install/update copies anything. Three moves, all reversible:
#   1. every ~/.claude symlink into ~/.aidex/ that is NOT a repo item is
#      materialised — the user's own skills that lived there keep working;
#      repo items are left as links for copy_item to replace.
#   2. install state that has a new home moves there (census-trust, backups).
#   3. ~/.aidex/ is renamed to ~/.aidex-to-delete-<date> with a README. Nothing
#      is deleted; the user decides when.
migrate_legacy() {
  legacy_present || return 0
  header "Migrating the pre-0.40 layout out of $LEGACY_DIR"

  local repo_items
  repo_items="$(collect_repo_items)"
  local sub link target name
  for sub in skills rules commands; do
    [ -d "$CLAUDE_DIR/$sub" ] || continue
    while IFS= read -r link; do
      target="$(readlink "$link")"
      case "$target" in "$LEGACY_DIR"/*) ;; *) continue ;; esac
      name="$(basename "$link")"
      if printf '%s\n' "$repo_items" | grep -qxF "$sub/$name"; then
        continue  # a suite item: copy_item replaces the link
      fi
      rm "$link"
      if [ -e "$target" ]; then
        if [ -d "$target" ]; then
          mkdir -p "$link"
          rsync -a --exclude='__pycache__/' --exclude='*.pyc' --exclude='.DS_Store' "$target/" "$link/"
        else
          cp -f "$target" "$link"
        fi
        info "materialised your own $sub/$name (was a link into $LEGACY_DIR)"
      else
        warn "dropped dangling link $sub/$name → $target"
      fi
    done < <(find "$CLAUDE_DIR/$sub" -maxdepth 1 -type l 2>/dev/null)
  done

  mkdir -p "$STATE_DIR"
  if [ -f "$LEGACY_DIR/.census-trust" ] && [ ! -e "$STATE_DIR/census-trust" ]; then
    mv "$LEGACY_DIR/.census-trust" "$STATE_DIR/census-trust"
    info "moved census-trust → $STATE_DIR/census-trust"
  fi
  if [ -d "$LEGACY_DIR/backups" ] && [ ! -e "$STATE_DIR/backups" ]; then
    mv "$LEGACY_DIR/backups" "$STATE_DIR/backups"
    info "moved backups → $STATE_DIR/backups"
  fi

  local parked="${LEGACY_DIR}-to-delete-$(date +%Y-%m-%d)"
  local n=1
  while [ -e "$parked" ]; do parked="${LEGACY_DIR}-to-delete-$(date +%Y-%m-%d)-$n"; n=$((n + 1)); done
  mv "$LEGACY_DIR" "$parked"
  cat > "$parked/README.txt" <<EOF
Parked by aidex install.sh v$VERSION on $(date +%Y-%m-%d).

This was ~/.aidex/, the pre-0.40 install layout (copies here, symlinks in
~/.claude/). The suite now installs straight into ~/.claude/skills, rules and
hooks as real files, with its state in ~/.claude/aidex/.

What was carried over before parking:
  - every ~/.claude link into this tree that was NOT a suite item was replaced
    by a real copy at the same path (your own skills keep working);
  - .census-trust and backups/ moved to ~/.claude/aidex/.

Nothing else here is referenced any more. Delete the directory when you are
sure; the installer will never touch it again.
EOF
  info "parked $LEGACY_DIR → $parked (nothing deleted)"
}

# ─────────────────────────────────────────────
# INSTALL (first time)
# ─────────────────────────────────────────────

do_install() {
  echo -e "${BOLD}aidex installer${NC}"
  echo "Source: $SCRIPT_DIR"
  echo "Target: $CLAUDE_DIR"

  if [ -f "$MANIFEST" ]; then
    echo ""
    warn "aidex is already installed. Use --update to update or --uninstall to remove."
    exit 1
  fi

  migrate_legacy

  mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/rules" "$CLAUDE_DIR/hooks" "$STATE_DIR"

  local items=()
  local installed=0
  local skipped=()

  header "Installing into $CLAUDE_DIR"
  while IFS= read -r item; do
    if ! dst_is_ours "$item"; then
      skipped+=("$item")
      warn "$item: $(item_dst "$item") exists and is not aidex's (skipped)"
      continue
    fi
    copy_item "$item"
    items+=("$item")
    info "$item"
    installed=$((installed + 1))
  done < <(collect_repo_items)

  write_manifest "${items[@]}"
  fix_exec_bits
  stamp_install

  echo ""
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "  ${GREEN}aidex installed successfully${NC} (v$VERSION)"
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Installed: $installed items"
  [ "${#skipped[@]}" -gt 0 ] && echo "  Skipped (name taken by a file of yours): ${skipped[*]}"
  echo ""
  echo -e "  ${BOLD}Next steps:${NC}"
  echo "  1. Restart Claude Code"
  echo "  2. In any project, ask Claude: /aidex"
  echo "     aidex will scan your ecosystem and help you set up"
  echo "     the right structure (skills, .context/, CLAUDE.md)."
  echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ─────────────────────────────────────────────
# UPDATE
# ─────────────────────────────────────────────

do_update() {
  echo -e "${BOLD}aidex updater${NC}"

  # An old-layout install has its manifest in ~/.aidex/; that is still "installed".
  if [ ! -f "$MANIFEST" ] && [ -f "$LEGACY_DIR/.manifest" ]; then
    # The legacy manifest listed the same item names; adopt it so the loop below
    # sees the (soon link-less) entries as ours to replace. Hooks are not carried:
    # only SHIPPED_HOOKS install now, and they are picked up as new items.
    mkdir -p "$STATE_DIR"
    grep -E '^(skills|rules)/' "$LEGACY_DIR/.manifest" | sort -u > "$MANIFEST" || true
  fi

  if [ ! -f "$MANIFEST" ]; then
    warn "aidex is not installed. Run install.sh first (without flags)."
    exit 1
  fi

  migrate_legacy

  local modified=()
  local new_items=()
  local removed=()
  local unchanged=0

  while IFS= read -r item; do
    local src="$SCRIPT_DIR/$item"
    local dst
    dst="$(item_dst "$item")"
    if [ -L "$dst" ] || [ ! -e "$dst" ] || ! in_manifest "$item"; then
      # Absent, still a legacy symlink, or present but unowned (a by-hand copy —
      # dst_is_ours adopts it only if byte-identical, else it is skipped).
      new_items+=("$item")
    elif [ -d "$src" ]; then
      if ! diff -rq -x '__pycache__' -x '*.pyc' -x '.DS_Store' "$src" "$dst" > /dev/null 2>&1; then
        modified+=("$item")
      else
        unchanged=$((unchanged + 1))
      fi
    else
      if ! diff -q "$src" "$dst" > /dev/null 2>&1; then
        modified+=("$item")
      else
        unchanged=$((unchanged + 1))
      fi
    fi
  done < <(collect_repo_items)

  # Items in the manifest but no longer shipped (removed upstream, or a hook
  # that left SHIPPED_HOOKS).
  local shipped
  shipped="$(collect_repo_items)"
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    printf '%s\n' "$shipped" | grep -qxF "$item" || removed+=("$item")
  done < <(read_manifest)

  header "Changes detected"

  if [ "${#modified[@]}" -eq 0 ] && [ "${#new_items[@]}" -eq 0 ] && [ "${#removed[@]}" -eq 0 ]; then
    info "Everything is up to date ($unchanged items unchanged)"
    fix_exec_bits
    # Still stamp the version: a release commit may bump VERSION= with no item changes.
    stamp_install
    exit 0
  fi

  for item in ${modified[@]+"${modified[@]}"}; do
    echo -e "  ${YELLOW}Modified:${NC}  $item"
  done
  for item in ${new_items[@]+"${new_items[@]}"}; do
    echo -e "  ${GREEN}New:${NC}       $item"
  done
  for item in ${removed[@]+"${removed[@]}"}; do
    echo -e "  ${RED}Removed:${NC}   $item (no longer shipped)"
  done
  echo "  Unchanged: $unchanged items"
  echo ""

  echo "  Options:"
  echo "    [1] Apply all changes (recommended)"
  echo "    [2] Show diff for each modified item, then ask"
  echo "    [3] Cancel"
  echo ""
  local choice
  choice=$(ask_choice "Choice" "1")

  # Interactive-update outcome tracking (choice 2): the manifest must reflect
  # what was ACTUALLY installed/kept — declined new items stay out; declined
  # removals stay in (so a later update re-offers them instead of orphaning).
  local accepted_new=()
  local applied_removals=()
  local declined_conventions=0
  local accepted_other_skill=0

  install_one() {
    local item="$1"
    if ! dst_is_ours "$item"; then
      warn "$item: $(item_dst "$item") exists and is not aidex's (skipped)"
      return 1
    fi
    copy_item "$item"
    return 0
  }

  case "$choice" in
    1)
      for item in ${modified[@]+"${modified[@]}"} ${new_items[@]+"${new_items[@]}"}; do
        install_one "$item" && info "Updated: $item" && accepted_new+=("$item") || true
      done
      for item in ${removed[@]+"${removed[@]}"}; do
        remove_item "$item"
        info "Removed: $item"
      done
      ;;
    2)
      for item in ${modified[@]+"${modified[@]}"}; do
        header "Diff: $item"
        if [ -d "$SCRIPT_DIR/$item" ]; then
          diff -rq -x '__pycache__' -x '*.pyc' -x '.DS_Store' "$SCRIPT_DIR/$item" "$(item_dst "$item")" 2>/dev/null || true
        else
          diff --color=auto "$(item_dst "$item")" "$SCRIPT_DIR/$item" 2>/dev/null || true
        fi
        echo ""
        local apply
        apply=$(ask_choice "Apply this change? (y/n)" "y")
        if [ "$apply" = "y" ]; then
          install_one "$item" && info "Updated: $item" || true
          case "$item" in skills/aidex-conventions) ;; skills/*) accepted_other_skill=1 ;; esac
        else
          warn "Skipped: $item"
          [ "$item" = "skills/aidex-conventions" ] && declined_conventions=1
        fi
      done
      for item in ${new_items[@]+"${new_items[@]}"}; do
        local apply
        apply=$(ask_choice "Install new item: $item? (y/n)" "y")
        if [ "$apply" = "y" ]; then
          if install_one "$item"; then
            info "Installed: $item"
            accepted_new+=("$item")
            case "$item" in skills/aidex-conventions) ;; skills/*) accepted_other_skill=1 ;; esac
          fi
        fi
      done
      for item in ${removed[@]+"${removed[@]}"}; do
        local apply
        apply=$(ask_choice "Remove $item (no longer shipped)? (y/n)" "y")
        if [ "$apply" = "y" ]; then
          remove_item "$item"
          info "Removed: $item"
          applied_removals+=("$item")
        fi
      done
      if [ "$declined_conventions" -eq 1 ] && [ "$accepted_other_skill" -eq 1 ]; then
        warn "You updated skills but declined skills/aidex-conventions — other skills source"
        warn "its scripts/_lib.sh at runtime; a version skew there can break them. Consider"
        warn "re-running --update and accepting aidex-conventions."
      fi
      ;;
    3)
      echo "  Cancelled."
      exit 0
      ;;
    *)
      # No fallback arm meant an unrecognized answer fell through to the manifest
      # write and the version stamp: nothing installed, yet the run printed
      # "Updated to vX" and the marker agreed. Refuse loudly instead.
      error "Unrecognized choice '$choice' — nothing was changed. Re-run with 1, 2 or 3."
      exit 1
      ;;
  esac

  # Manifest from ACTUAL outcomes, never blindly from the repo.
  local all_items=()
  if [ "$choice" = "2" ]; then
    while IFS= read -r item; do
      [ -n "$item" ] || continue
      local drop=0 r
      for r in ${applied_removals[@]+"${applied_removals[@]}"}; do
        [ "$item" = "$r" ] && drop=1
      done
      [ "$drop" -eq 0 ] && all_items+=("$item")
    done < <(read_manifest)
    for item in ${accepted_new[@]+"${accepted_new[@]}"}; do
      all_items+=("$item")
    done
  else
    # Apply-all: every shipped item whose destination is ours was installed;
    # a skipped (user-owned) name stays out of the manifest.
    while IFS= read -r item; do
      [ -n "$item" ] || continue
      local keep=0 r
      for r in ${removed[@]+"${removed[@]}"}; do [ "$item" = "$r" ] && keep=1; done
      [ "$keep" -eq 0 ] && all_items+=("$item")
    done < <(read_manifest)
    for item in ${accepted_new[@]+"${accepted_new[@]}"}; do
      all_items+=("$item")
    done
  fi
  write_manifest "${all_items[@]}"
  fix_exec_bits
  stamp_install

  header "Done"
  echo "  Updated to v$VERSION"
  echo "  Restart Claude Code to load changes."
}

# ─────────────────────────────────────────────
# UNINSTALL
# ─────────────────────────────────────────────

do_uninstall() {
  echo -e "${BOLD}aidex uninstaller${NC}"

  # The manifest is the ownership inventory: without it every branch below walks
  # an empty list and reports success having removed nothing. Refuse loudly.
  if [ ! -s "$MANIFEST" ]; then
    error "manifest missing — run install.sh to rebuild it before uninstalling"
    echo "  (expected at $MANIFEST; a bare re-install repairs it without touching your files)"
    exit 1
  fi

  echo ""
  echo "  This removes exactly what aidex installed (the manifest entries) and its"
  echo "  state in $STATE_DIR. Your own skills, rules and hooks are not touched."
  echo ""
  echo "    [1] Remove aidex"
  echo "    [2] Cancel"
  echo ""
  local choice
  choice=$(ask_choice "Choice" "2")

  case "$choice" in
    1)
      local removed=0
      header "Removing aidex-managed items from $CLAUDE_DIR"
      while IFS= read -r item; do
        [ -n "$item" ] || continue
        if [ -e "$(item_dst "$item")" ] || [ -L "$(item_dst "$item")" ]; then
          remove_item "$item"
          info "$item"
          removed=$((removed + 1))
        fi
      done < <(read_manifest)
      # backups/ is the user's data (project .context/ snapshots), not install state.
      if [ -d "$STATE_DIR/backups" ]; then
        rm -f "$STATE_DIR/manifest" "$STATE_DIR/version" "$STATE_DIR/commit"
        warn "kept $STATE_DIR/backups (your .context/ snapshots) — delete it yourself if unwanted"
      else
        rm -rf "$STATE_DIR"
      fi
      header "Done"
      echo "  Removed: $removed items"
      echo "  Restart Claude Code to apply changes."
      ;;
    *)
      echo "  Cancelled."
      exit 0
      ;;
  esac
}

# ─────────────────────────────────────────────
# DOCTOR (health check)
# ─────────────────────────────────────────────

run_doctor() {
  echo "aidex doctor"
  echo ""

  local fail_count=0

  # 1. version marker matches the repo.
  if [ -f "$STATE_DIR/version" ]; then
    local installed_version
    installed_version="$(cat "$STATE_DIR/version")"
    if [ "$installed_version" = "$VERSION" ]; then
      echo "PASS: version $installed_version"
    else
      echo "FAIL: version mismatch — installed $installed_version, repo $VERSION"
      fail_count=$((fail_count + 1))
    fi
  else
    echo "FAIL: $STATE_DIR/version not found"
    fail_count=$((fail_count + 1))
  fi

  # 1b. Content drift: same version, different commit. Silent when either side
  # has no commit to compare — an absent marker is not evidence of drift.
  local repo_sha
  repo_sha="$(repo_commit)"
  if [ -n "$repo_sha" ] && [ -f "$STATE_DIR/commit" ]; then
    local installed_sha
    installed_sha="$(cat "$STATE_DIR/commit")"
    if [ "$installed_sha" = "$repo_sha" ]; then
      echo "PASS: installed from commit $installed_sha"
    else
      echo "FAIL: content drift — installed from $installed_sha, repo HEAD is $repo_sha (run ./install.sh --update)"
      fail_count=$((fail_count + 1))
    fi
  fi

  # 2. The old layout is gone. A surviving ~/.aidex/ means links may still point
  # into it — and it is exactly the unmanaged pile this layout was retired for.
  if legacy_present; then
    echo "FAIL: legacy $LEGACY_DIR still present — run ./install.sh --update to migrate it"
    fail_count=$((fail_count + 1))
  else
    echo "PASS: no legacy $LEGACY_DIR"
  fi

  # 3. Manifest present; every entry exists as a REAL file or directory. A symlink
  # is the old layout, or the user re-linking a skill by hand.
  if [ -f "$MANIFEST" ]; then
    local missing=() linked=()
    local item dst
    while IFS= read -r item; do
      [ -z "$item" ] && continue
      dst="$(item_dst "$item")"
      if [ -L "$dst" ]; then
        linked+=("$item")
      elif [ ! -e "$dst" ]; then
        missing+=("$item")
      fi
    done < "$MANIFEST"
    if [ "${#missing[@]}" -eq 0 ] && [ "${#linked[@]}" -eq 0 ]; then
      echo "PASS: manifest present, all $(grep -c . "$MANIFEST") entries installed as real files"
    fi
    if [ "${#missing[@]}" -gt 0 ]; then
      echo "FAIL: manifest entries missing: ${missing[*]}"
      fail_count=$((fail_count + 1))
    fi
    if [ "${#linked[@]}" -gt 0 ]; then
      echo "FAIL: manifest entries that are symlinks, not copies: ${linked[*]}"
      fail_count=$((fail_count + 1))
    fi
  else
    echo "FAIL: $MANIFEST not found"
    fail_count=$((fail_count + 1))
  fi

  # 4. Nothing named like the suite sits outside the manifest. An aidex-* skill
  # directory that aidex did not install is a leftover of a by-hand copy or of a
  # removed skill, and it loads in every session.
  if [ -d "$CLAUDE_DIR/skills" ]; then
    local stray=() d name
    for d in "$CLAUDE_DIR"/skills/aidex*/; do
      [ -d "$d" ] || continue
      name="$(basename "$d")"
      in_manifest "skills/$name" || stray+=("$name")
    done
    if [ "${#stray[@]}" -eq 0 ]; then
      echo "PASS: no unmanaged aidex-* skill directories"
    else
      echo "FAIL: unmanaged aidex-* skill directories in $CLAUDE_DIR/skills: ${stray[*]}"
      fail_count=$((fail_count + 1))
    fi
  else
    echo "FAIL: $CLAUDE_DIR/skills not found"
    fail_count=$((fail_count + 1))
  fi

  # 5. Every installed skill script is executable.
  local non_exec=()
  local script item
  while IFS= read -r item; do
    case "$item" in skills/*) ;; *) continue ;; esac
    while IFS= read -r script; do
      [ -x "$script" ] || non_exec+=("$script")
    done < <(find "$(item_dst "$item")/scripts" -maxdepth 1 -name '*.sh' 2>/dev/null)
  done < <(read_manifest)
  if [ "${#non_exec[@]}" -eq 0 ]; then
    echo "PASS: all skill scripts executable"
  else
    echo "FAIL: non-executable script(s): ${non_exec[*]}"
    fail_count=$((fail_count + 1))
  fi

  # 6. python3 on PATH.
  if command -v python3 >/dev/null 2>&1; then
    echo "PASS: python3 on PATH ($(command -v python3))"
  else
    echo "FAIL: python3 not found on PATH"
    fail_count=$((fail_count + 1))
  fi

  # 7. Every manifest rule is a regular file in ~/.claude/rules/ — the only surface
  # that loads. Reported separately from check 3 because a rule that does not load
  # is silent in every session (deep audit 2026-07-25).
  if [ -f "$MANIFEST" ] && grep -q '^rules/' "$MANIFEST" 2>/dev/null; then
    local rule_issues=() rule_total=0 entry base f
    while IFS= read -r entry; do
      case "$entry" in rules/*) ;; *) continue ;; esac
      rule_total=$((rule_total + 1))
      base="$(basename "$entry")"
      f="$CLAUDE_DIR/rules/$base"
      if [ -L "$f" ]; then
        rule_issues+=("$base (symlink — the old layout)")
      elif [ ! -f "$f" ]; then
        rule_issues+=("$base (missing from $CLAUDE_DIR/rules/ — never loads)")
      fi
    done < "$MANIFEST"
    if [ "${#rule_issues[@]}" -eq 0 ]; then
      echo "PASS: $rule_total aidex rule(s) in $CLAUDE_DIR/rules/"
    else
      echo "FAIL: aidex rule(s) not loading: ${rule_issues[*]}"
      fail_count=$((fail_count + 1))
    fi
  fi

  # 8. Shipped hooks present and executable.
  local hook_issues=() hook
  for hook in $SHIPPED_HOOKS; do
    [ -f "$SCRIPT_DIR/hooks/$hook" ] || continue
    if ! in_manifest "hooks/$hook"; then
      hook_issues+=("$hook (not in the manifest — run ./install.sh --update)")
    elif [ ! -x "$CLAUDE_DIR/hooks/$hook" ]; then
      hook_issues+=("$hook (missing or not executable)")
    fi
  done
  if [ "${#hook_issues[@]}" -eq 0 ]; then
    echo "PASS: shipped hooks present and executable"
  else
    echo "FAIL: hook(s) missing or not executable: ${hook_issues[*]}"
    fail_count=$((fail_count + 1))
  fi

  echo ""
  if [ "$fail_count" -eq 0 ]; then
    echo "aidex doctor: all checks passed"
    return 0
  else
    echo "aidex doctor: $fail_count check(s) failed"
    return 1
  fi
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
  --doctor)
    run_doctor
    exit $?
    ;;
  --help|-h)
    echo "Usage: install.sh [--update | --uninstall | --doctor | --help]"
    echo ""
    echo "  (no flags)    First-time install into ~/.claude/ (skills, rules, hooks)"
    echo "  --update      Update existing installation from repo (migrates a pre-0.40 ~/.aidex/ layout)"
    echo "  --uninstall   Remove what aidex installed (interactive)"
    echo "  --doctor      Run install health checks (PASS/FAIL report)"
    echo "  --help        Show this help"
    ;;
  "")
    for tool in rsync python3; do
      command -v "$tool" >/dev/null 2>&1 || { error "$tool not found on PATH — install it and re-run"; exit 1; }
    done
    do_install
    ;;
  *)
    echo "Unknown option: $1"
    echo "Run install.sh --help for usage."
    exit 1
    ;;
esac
