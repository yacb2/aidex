#!/usr/bin/env bash
# migrate-profiles.sh — move a project's profiles from the .context/ root into
# .context/profiles/ under the canon names (00-global.md §12), and rewrite the
# .gitignore whitelist lines that name the old paths.
#
# Usage: migrate-profiles.sh <project-root> [--apply] [--include-deploy]
#
# Dry-run by default: prints one "would ..." line per action and changes nothing.
# --apply does the moves (git mv when the file is tracked, plain mv + a note when it is
# untracked or ignored; prints UNTRACKED-MOVED, never git adds it) and the .gitignore
# rewrite. Never commits.
# deploy-profile.md is skipped unless --include-deploy: the fleet's synced bp-ops
# still reads the old path.
# Refuses (exit 1, nothing touched) when a profile to move has uncommitted changes.
# Also refuses --apply when .gitignore itself has uncommitted changes.
# Whitelist lines inside a `# BP-ROOT-WHITELIST:START`..`END` block are reported, never
# rewritten: the dashboard boilerplate owns that block. When such a block exists, the new
# `!.context/profiles/` lines go right after its END marker (fork-owned area, last match
# wins) instead of at the first old line.
set -uo pipefail

APPLY=0 DEPLOY=0 ROOT=""
for a in "$@"; do
  case "$a" in
    -h|--help) sed -n '6,/^set -uo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    --apply) APPLY=1 ;;
    --include-deploy) DEPLOY=1 ;;
    -*) echo "error: unknown option: $a" >&2; exit 2 ;;
    *) ROOT="$a" ;;
  esac
done
[[ -n "$ROOT" && -d "$ROOT/.context" ]] || { echo "usage: migrate-profiles.sh <project-root> [--apply] [--include-deploy]" >&2; exit 2; }
cd "$ROOT" || exit 2

# old name -> new name (the canon table, 00-global.md §12)
PAIRS="artifact-style.md:artifact.md communication-style.md:communication.md testing-profile.md:testing.md ui-contract.md:ui-contract.md"
[[ "$DEPLOY" -eq 1 ]] && PAIRS="$PAIRS deploy-profile.md:deploy.md"

in_git=0; git rev-parse --git-dir >/dev/null 2>&1 && in_git=1
tracked() { [[ "$in_git" -eq 1 ]] && git ls-files --error-unmatch -- "$1" >/dev/null 2>&1; }

# 1. Refuse on uncommitted changes to a profile that would move.
for pair in $PAIRS; do
  old=".context/${pair%%:*}"
  [[ -f "$old" ]] || continue
  if tracked "$old" && [[ -n "$(git status --porcelain -- "$old")" ]]; then
    echo "refused: $old has uncommitted changes — commit or discard them first" >&2
    exit 1
  fi
done

if [[ "$APPLY" -eq 1 ]] && tracked .gitignore && [[ -n "$(git status --porcelain -- .gitignore)" ]]; then
  echo "refused: .gitignore has uncommitted changes — commit or discard them first" >&2
  exit 1
fi

# 2. Move the profiles.
for pair in $PAIRS; do
  old=".context/${pair%%:*}" new=".context/profiles/${pair##*:}"
  [[ -f "$old" ]] || continue
  if [[ -e "$new" ]]; then echo "skip: $old (target $new already exists)"; continue; fi
  if tracked "$old"; then how="git mv"; else how="mv (untracked or ignored: not in git history)"; fi
  if [[ "$APPLY" -eq 0 ]]; then echo "would move: $old -> $new [$how]"; continue; fi
  mkdir -p .context/profiles
  if tracked "$old"; then git mv "$old" "$new"; else mv "$old" "$new"; fi
  if tracked "$new"; then echo "moved: $old -> $new [git mv]"
  else echo "UNTRACKED-MOVED $new (now versionable: check for secrets, then git add)"; fi
done
if [[ "$DEPLOY" -eq 0 && -f .context/deploy-profile.md ]]; then
  echo "skip: .context/deploy-profile.md (synced bp-ops still reads it; pass --include-deploy to move it)"
fi

# 3. Rewrite the whitelist lines for the profiles being migrated.
if [[ -f .gitignore ]]; then
  alts=""; for pair in $PAIRS; do n="${pair%%:*}"; alts="$alts|${n//./\\.}"; done
  OLD_RE="^!\\.context/(${alts#|})$"
  bpend=0; grep -q '^# BP-ROOT-WHITELIST:END' .gitignore && bpend=1
  have=0; grep -qx '!\.context/profiles/' .gitignore && have=1   # never add the whitelist twice
  tmp="$(mktemp "${TMPDIR:-/tmp}/aidex.XXXXXX")"
  awk -v re="$OLD_RE" -v done_init="$have" -v bpend="$bpend" '
    BEGIN { done = done_init }
    /^# BP-ROOT-WHITELIST:START/ { bp = 1 }
    {
      if ($0 ~ re) {
        if (!done) {
          done = 1
          if (bpend) pending = 1
          else { print "!.context/profiles/"; print "!.context/profiles/**" }
        }
        if (bp) { print "report: " $0 " (inside BP-ROOT-WHITELIST, left for the boilerplate)" > "/dev/stderr"; print }
        else print "rewrote: " $0 > "/dev/stderr"
        next
      }
      print
    }
    /^# BP-ROOT-WHITELIST:END/ {
      bp = 0
      if (pending) {
        print "!.context/profiles/"; print "!.context/profiles/**"; pending = 0
        print "placed: !.context/profiles/ + ** right after BP-ROOT-WHITELIST:END (fork-owned area, last match wins)" > "/dev/stderr"
      }
    }
  ' .gitignore > "$tmp" 2> "$tmp.log"
  if [[ -s "$tmp.log" ]]; then
    while IFS= read -r l; do
      case "$l" in
        rewrote:*) if [[ "$APPLY" -eq 1 ]]; then echo ".gitignore ${l}"; else echo "would rewrite .gitignore line: ${l#rewrote: }"; fi ;;
        placed:*) if [[ "$APPLY" -eq 1 ]]; then echo ".gitignore ${l}"; else echo "would place: ${l#placed: }"; fi ;;
        *) echo ".gitignore ${l}" ;;
      esac
    done < "$tmp.log"
  fi
  if [[ "$APPLY" -eq 1 ]] && ! cmp -s .gitignore "$tmp"; then cat "$tmp" > .gitignore; fi
  rm -f "$tmp" "$tmp.log"
fi
exit 0
