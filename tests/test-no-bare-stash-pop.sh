#!/usr/bin/env bash
# test-no-bare-stash-pop.sh — the revert check must never touch the delegate's working tree
# (BL-849). It runs the new tests against HEAD in a throwaway worktree.
#
# Part 0 (self-check): the scanner is run on fixtures: zero files, forbidden rows, allowed rows.
# Part 1 (text): agents/*.md, skills/testing/**/*.md and human-verification-conventions.md
#   may not contain any `git stash`, a WIP commit or a reset to HEAD~ / HEAD^. Zero files
#   scanned is a failure. impl-sonnet.md and the conventions file must both document the
#   throwaway worktree.
# Part 2 (behaviour): each line of the bash block in agents/impl-sonnet.md runs as its own
#   `bash -c` (no shell state carried) in a scratch repo holding two same-basename edits, a
#   staged rename with an edit, a staged deletion and an added test file, next to another
#   session's stash entry. The delegate's tree must be byte-identical afterwards, the stash
#   list unchanged, and the test run against HEAD must fail.
#
# Usage: bash tests/test-no-bare-stash-pop.sh [ROOT]   (ROOT defaults to the repo root)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ROOT="${1:-$REPO_ROOT}"
fail=0
bad() { echo "FAIL: $*"; fail=1; }

# scan ROOT -> prints hits, returns 1 on hits or zero files
scan() {
  local root="$1" f hits=""
  local -a files=()
  while IFS= read -r f; do files+=("$f"); done < <(
    { ls "$root"/agents/*.md; find "$root/skills/testing" -name '*.md' 2>/dev/null
      ls "$root"/skills/conventions/references/human-verification-conventions.md; } 2>/dev/null)
  if [ "${#files[@]}" -eq 0 ]; then echo "scanned 0 files under $root"; return 1; fi
  hits="$(grep -nEi 'git[[:space:]]+stash|commit.*(-[a-z]*m|--message)[[:space:]=]*["'"'"']?wip|reset.*HEAD[~^]' "${files[@]}")"
  if [ -n "$hits" ]; then printf '%s\n' "$hits"; return 1; fi
  echo "${#files[@]} files"; return 0
}

# ---- Part 0: self-check of the scanner
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/empty"
scan "$tmp/empty" >/dev/null && bad "self-check: zero files must fail"
fx="$tmp/fx"
check_row() { # want(forbid|allow) line
  rm -rf "$fx"; mkdir -p "$fx/agents"; printf '%s\n' "$2" > "$fx/agents/x.md"
  if scan "$fx" >/dev/null; then [ "$1" = allow ] || bad "self-check: must forbid: $2"
  else [ "$1" = forbid ] || bad "self-check: must allow: $2"; fi
}
for row in 'run `git stash pop` now' 'run `git  stash  pop`' 'git stash -- a' 'git stash push -u -m t -- a' \
           'git stash apply "$SHA"' 'git stash list' 'Never pop: `git stash pop` (see `git stash list`).' \
           'git commit -m wip' 'git commit -am WIP' 'git commit --message wip' 'git commit -m "wip"' \
           'git reset --soft HEAD~1' 'git reset HEAD^'; do check_row forbid "$row"; done
for row in 'git worktree add --detach ../revert-check-$(basename "$PWD") HEAD' 'git worktree remove --force ../revert-check-$(basename "$PWD")' \
           'Never touch the stash or make a WIP-free commit.' 'git reset -q -- a.ts' 'git commit -m "feat: add x"'; do
  check_row allow "$row"; done

# ---- Part 1: the real text
out="$(scan "$ROOT")" || bad "text advises a forbidden form:
$out"
for f in agents/impl-sonnet.md skills/conventions/references/human-verification-conventions.md; do
  for form in 'git worktree add --detach' 'git worktree remove --force'; do
    grep -qF "$form" "$ROOT/$f" || bad "$f does not document: $form"
  done
done

# ---- Part 2: run the documented steps, one bash -c per line
doc="$ROOT/agents/impl-sonnet.md"
block="$(awk '/^```bash/{f=1;next} /^```/{f=0} f' "$doc")"
if [ -z "$block" ]; then bad "no bash block in $doc"; else
  r="$tmp/repo"; mkdir -p "$r/src/a" "$r/src/b" "$r/t" && cd "$r" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  printf 'A1\n' > src/a/index.ts; printf 'B1\n' > src/b/index.ts
  printf 'old\n' > old.ts; printf 'gone\n' > gone.ts; printf 'seed\n' > seed.ts
  git add -A && git commit -qm base
  printf 'other\n' >> seed.ts && git stash push -q -m other-session
  stash_before="$(git stash list --format='%H %gs')"
  [ -n "$stash_before" ] || bad "scratch: could not seed the stash"
  printf 'A2\n' > src/a/index.ts; printf 'B2\n' > src/b/index.ts
  git mv old.ts new.ts; printf 'NEWEDIT\n' >> new.ts; git rm -q gone.ts; printf 'added\n' > added.ts
  git add src/a/index.ts new.ts
  printf '[ "$(cat src/a/index.ts)" = A2 ] || { echo "EXPECTED-A2 got $(cat src/a/index.ts)"; exit 1; }\n' > t/new-test.sh
  bash t/new-test.sh >/dev/null || bad "scratch: new test must pass on the delegate's tree"
  snap() { find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$(shasum < "$f")" "$f"; done; git status --short; }
  before="$(snap)"
  n=0; test_rc=""
  while IFS= read -r step; do
    [ -n "$step" ] || continue
    case "$step" in '#'*) continue;; esac
    step="${step//<test dir>/t}"; step="${step//<test file>/t/new-test.sh}"; step="${step//<test command>/bash t/new-test.sh}"
    n=$((n+1))
    log="$(bash -c "$step" 2>&1)"; rc=$?
    if [ "$rc" -ne 0 ]; then
      case "$step" in *"bash t/new-test.sh"*) test_rc="$rc"; case "$log" in *EXPECTED-A2*) ;; *) bad "test against HEAD failed for the wrong reason: $log";; esac;;
        *) bad "step $n exited $rc: $step: $log";; esac
    else
      case "$step" in *"bash t/new-test.sh"*) bad "the test must FAIL against HEAD but passed";; esac
    fi
  done <<< "$block"
  [ "$n" -ge 3 ] || bad "documented block has only $n steps"
  [ -n "$test_rc" ] || bad "no documented step ran the test"
  after="$(snap)"
  [ "$before" = "$after" ] || bad "delegate tree differs after the documented steps:
$(diff <(echo "$before") <(echo "$after"))"
  [ "$stash_before" = "$(git stash list --format='%H %gs')" ] || bad "stash list changed"
  [ "$(git worktree list | wc -l | tr -d ' ')" = 1 ] || bad "throwaway worktree left behind: $(git worktree list)"
  ! ls -d "$tmp"/revert-check-* >/dev/null 2>&1 || bad "throwaway directory left behind"
  cd "$REPO_ROOT"
fi

[ "$fail" -eq 0 ] && echo "PASS: no stash or WIP advice, scanner self-checked, documented worktree steps leave the delegate's tree untouched and fail against HEAD"
exit "$fail"
