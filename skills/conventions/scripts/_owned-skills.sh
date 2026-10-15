#!/usr/bin/env bash
# _owned-skills.sh — which skill directories aidex owns. Sourceable, not a test.
#
# The skills root is the plugin checkout, aidex-only by construction (install.sh and
# its ~/.claude/aidex/manifest are retired, docs/retired/), so every directory under
# <root>/skills that holds a SKILL.md is owned.
#
# Deliberately sets no shell options: its consumers run `set -uo pipefail` and
# count failures instead of aborting, so sourcing `_lib.sh` (which sets `-e`)
# would change their control flow. This file is prefixed `_` so run-all.sh's
# `test[-_]*` discovery globs do not run it as a test with zero assertions.
#
# Usage:  . "$SCRIPT_DIR/_owned-skills.sh"
#         while IFS= read -r d; do ...; done < <(aidex_owned_skill_dirs "$ROOT")

# aidex_owned_skill_dirs <root> — one absolute skill directory per line.
# <root> is the repo checkout.
aidex_owned_skill_dirs() {
  local root="$1" d

  for d in "$root"/skills/*/; do
    [ -f "$d/SKILL.md" ] || continue
    printf '%s\n' "${d%/}"
  done
}
