#!/usr/bin/env bash
# migrate-communications.sh — rename pre-canonical body filenames to body.md.
# Usage: migrate-communications.sh
#
# The canonical layout (received/ + sent/ + meetings/, body.md, status) shipped in
# 1898b60, but nothing enforced the filename, so entries written AFTER that commit
# still carry `email.md` / `conversation.md` (RETRO-49). validate.py now reports them
# as `communication-legacy-body-name`; this is the pass that fixes them.
#
# Running it IS the opt-in — the canon's "manual and opt-in, never auto-migrate" rule
# is about auditors moving files behind the user's back, not about a command someone
# typed. It never touches attachments, never crosses out of .context/communications/,
# and refuses any rename that would clobber an existing body.md.
#
# There is no --dry-run: validate.py's `communication-legacy-body-name` finding IS the
# preview, and it costs nothing to run first.
#
# Exit 0 when the tree is clean or every rename succeeded; 1 when a rename was
# refused; 2 on a usage error.

set -euo pipefail

LEGACY_NAMES=(email.md conversation.md)

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m' C_RESET=$'\033[0m'
else
  C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_RESET=''
fi
info() { printf '%s%s%s\n' "$C_BLUE" "$*" "$C_RESET" >&2; }
ok()   { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET" >&2; }
warn() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
err()  { printf '%s%s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }
die()  { err "error: $*"; exit 2; }

# Shared resolver — never a private copy (pinned by test-find-project-root.sh).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) printf 'Usage: migrate-communications.sh\n' >&2; exit 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

ROOT="$(find_project_root)"
COMMS="$ROOT/.context/communications"

if [[ ! -d "$COMMS" ]]; then
  info "no .context/communications/ in $ROOT — nothing to migrate"
  exit 0
fi

renamed=0
refused=0

# Only files sitting directly inside {received,sent,meetings}/<YYYY-MM-DD>-<slug>/
# are entry bodies. Anything shallower or deeper is not ours to rename.
for sub in received sent meetings; do
  [[ -d "$COMMS/$sub" ]] || continue
  for entry in "$COMMS/$sub"/*/; do
    [[ -d "$entry" ]] || continue
    base="$(basename "$entry")"
    [[ "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}- ]] || continue
    for legacy in "${LEGACY_NAMES[@]}"; do
      src="$entry$legacy"
      [[ -f "$src" ]] || continue
      dst="$entry""body.md"
      rel="${src#"$ROOT"/}"
      if [[ -e "$dst" ]]; then
        warn "REFUSED  $rel — body.md already exists in this entry; merge by hand"
        refused=$((refused + 1))
        continue
      fi
      mv "$src" "$dst"
      ok "RENAMED  $rel -> ${dst#"$ROOT"/}"
      renamed=$((renamed + 1))
    done
  done
done

if [[ "$renamed" -eq 0 && "$refused" -eq 0 ]]; then
  ok "communications: no pre-canonical body filenames found"
  exit 0
fi

ok "communications: $renamed file(s) renamed, $refused refused"

# A rename changes what `related:` cross-refs point at only by folder, never by file
# (D-03 markers name the folder), so nothing downstream needs rewriting.
[[ "$refused" -gt 0 ]] && exit 1
exit 0
