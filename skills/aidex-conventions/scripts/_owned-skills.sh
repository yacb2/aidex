#!/usr/bin/env bash
# _owned-skills.sh — which skill directories aidex owns. Sourceable, not a test.
#
# Installed, the skills root is ~/.claude/skills, which also holds whatever
# skills the user put there. A guard that walks that root judges files this repo
# does not ship and FAILs on a clean tree, while the repo copy — where the root
# is aidex-only by construction — prints OK. That is BL-115, and it was found and
# fixed three separate times, once per walker, in three separate copies of the
# same ten-line rule. This file is the fourth copy's replacement.
#
# `~/.claude/aidex/manifest` is install.sh's ownership record: one entry per
# installed item, always exactly two segments (`skills/<name>`, `rules/<file>`,
# `hooks/<file>`) — see install.sh `collect_items` / `write_manifest`.
#
# A PRESENT manifest is authoritative even when it yields nothing. Falling back
# to "scan everything" on an empty or corrupt manifest is BL-115 reopened by a
# broken install, silently. Every consumer already FAILs loudly on an empty set
# (`checked > 0`, `${#ASSETS[@]} -gt 0`), which is the right verdict there.
#
# Deliberately sets no shell options: its consumers run `set -uo pipefail` and
# count failures instead of aborting, so sourcing `_lib.sh` (which sets `-e`)
# would change their control flow. This file is prefixed `_` so run-all.sh's
# `test[-_]*` discovery globs do not run it as a test with zero assertions.
#
# Usage:  . "$SCRIPT_DIR/_owned-skills.sh"
#         while IFS= read -r d; do ...; done < <(aidex_owned_skill_dirs "$ROOT")

# aidex_owned_skill_dirs <root> — one absolute skill directory per line.
# <root> is the install root (~/.claude) or the repo checkout.
aidex_owned_skill_dirs() {
  local root="$1" manifest entry name d

  manifest="$root/aidex/manifest"
  [ -f "$manifest" ] || manifest="$root/.manifest"   # pre-0.40 layout

  if [ -f "$manifest" ]; then
    while IFS= read -r entry; do
      case "$entry" in
        skills/*/*) continue ;;      # deeper than install.sh ever writes
        skills/?*)  name="${entry#skills/}" ;;
        *)          continue ;;
      esac
      [ -f "$root/skills/$name/SKILL.md" ] || continue
      printf '%s\n' "$root/skills/$name"
    done < "$manifest"
    return 0
  fi

  # No manifest at all: the repo checkout, aidex-only by construction.
  for d in "$root"/skills/*/; do
    [ -f "$d/SKILL.md" ] || continue
    printf '%s\n' "${d%/}"
  done
}
