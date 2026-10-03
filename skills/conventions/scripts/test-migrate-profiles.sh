#!/usr/bin/env bash
# test-migrate-profiles.sh — migrate-profiles.sh on throwaway git repos (BL-674).
# Layer: script integration (real git, temp dir). Cells: dry-run changes nothing, --apply
# moves with git mv and rewrites the whitelist once, a dirty profile is refused, deploy is
# skipped without --include-deploy, and a BP-ROOT-WHITELIST block is reported, not edited.
#
# Run with: bash skills/conventions/scripts/test-migrate-profiles.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/migrate-profiles.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# repo <dir>: committed artifact-style, testing-profile, deploy-profile and a whitelist
mkrepo() {
  local d="$1"; mkdir -p "$d/.context"; ( cd "$d" && git init -q
    echo a > .context/artifact-style.md; echo t > .context/testing-profile.md; echo d > .context/deploy-profile.md
    printf '.context/*\n!.context/artifact-style.md\n!.context/testing-profile.md\n!.context/deploy-profile.md\n# BP-ROOT-WHITELIST:START\n!.context/testing-profile.md\n# BP-ROOT-WHITELIST:END\n' > .gitignore
    git add -f -A && git -c user.email=a@b -c user.name=n commit -qm init )
}

# 1. dry-run changes nothing
R="$TMP/dry"; mkrepo "$R"
before="$(cd "$R" && git status --porcelain; cat .gitignore)"
out="$(bash "$SCRIPT" "$R")"
after="$(cd "$R" && git status --porcelain; cat .gitignore)"
[[ "$before" == "$after" ]] || fail "dry-run changed the tree"
[[ -f "$R/.context/artifact-style.md" && ! -e "$R/.context/profiles" ]] || fail "dry-run moved a file"
[[ "$out" == *"would move: .context/artifact-style.md -> .context/profiles/artifact.md"* ]] || fail "dry-run did not announce the move: $out"

# 2. --apply moves with git mv and rewrites the whitelist once
R="$TMP/apply"; mkrepo "$R"
out="$(bash "$SCRIPT" "$R" --apply)"
[[ -f "$R/.context/profiles/artifact.md" && -f "$R/.context/profiles/testing.md" ]] || fail "apply did not move the profiles"
[[ ! -e "$R/.context/artifact-style.md" && ! -e "$R/.context/testing-profile.md" ]] || fail "apply left root copies"
st="$(cd "$R" && git status --porcelain)"
[[ "$st" == *"R  .context/artifact-style.md -> .context/profiles/artifact.md"* ]] || fail "the move was not a git mv (rename not staged)"
[[ "$(grep -c '^!\.context/profiles/$' "$R/.gitignore")" == 1 && "$(grep -c '^!\.context/profiles/\*\*$' "$R/.gitignore")" == 1 ]] || fail "profiles whitelist not written exactly once: $(cat "$R/.gitignore")"
grep -q '^!\.context/artifact-style\.md$' "$R/.gitignore" && fail "old artifact whitelist line survived"
[[ "$(git -C "$R" rev-list --count HEAD)" == 1 ]] || fail "the script committed"
# the new whitelist really un-ignores the moved files
( cd "$R" && git check-ignore --no-index -q .context/profiles/artifact.md ) && fail "moved profile is still ignored"

# 3. deploy skipped without the flag, moved with it; its whitelist line stays when skipped
[[ -f "$R/.context/deploy-profile.md" ]] || fail "deploy-profile.md was moved without --include-deploy"
grep -q '^!\.context/deploy-profile\.md$' "$R/.gitignore" || fail "deploy whitelist line rewritten while deploy was skipped"
[[ "$out" == *"skip: .context/deploy-profile.md"* ]] || fail "deploy skip not reported: $out"
( cd "$R" && git add -A && git -c user.email=a@b -c user.name=n commit -qm step1 )
bash "$SCRIPT" "$R" --apply --include-deploy >/dev/null
[[ -f "$R/.context/profiles/deploy.md" && ! -e "$R/.context/deploy-profile.md" ]] || fail "--include-deploy did not move deploy"

# 4. BP-ROOT-WHITELIST block is reported, never edited
grep -q '^# BP-ROOT-WHITELIST:START$' "$R/.gitignore" && \
  [[ "$(sed -n '/BP-ROOT-WHITELIST:START/,/BP-ROOT-WHITELIST:END/p' "$R/.gitignore" | grep -c '^!\.context/testing-profile\.md$')" == 1 ]] \
  || fail "a line inside the BP block was rewritten"
[[ "$out" == *"inside BP-ROOT-WHITELIST"* ]] || fail "BP block line not reported: $out"

# 4b. real fork shape: pre-block whitelist line, then a BP block with `*` and `!.context/` lines.
# The new lines go right after END (last match wins) and the moved file is really un-ignored.
R="$TMP/fork"; mkdir -p "$R/.context"; ( cd "$R" && git init -q && echo a > .context/artifact-style.md
  printf '!.context/artifact-style.md\n# BP-ROOT-WHITELIST:START\n.context/*\n!.context/\n!.context/testing-profile.md\n# BP-ROOT-WHITELIST:END\n' > .gitignore
  git add -f -A && git -c user.email=a@b -c user.name=n commit -qm init )
out="$(bash "$SCRIPT" "$R" --apply)"
[[ "$out" == *"inside BP-ROOT-WHITELIST"* ]] || fail "fork: BP block line not reported: $out"
[[ "$out" == *"right after BP-ROOT-WHITELIST:END"* ]] || fail "fork: placement after END not announced: $out"
[[ "$(grep -n '' "$R/.gitignore" | sed -n '/BP-ROOT-WHITELIST:END/,$p' | cut -d: -f2- | tr '\n' ' ')" == "# BP-ROOT-WHITELIST:END !.context/profiles/ !.context/profiles/** " ]] || fail "fork: lines not right after END: $(cat "$R/.gitignore")"
( cd "$R" && git check-ignore --no-index -q .context/profiles/artifact.md ) && fail "fork: moved file still ignored"
# idempotence: a second --apply leaves .gitignore byte-identical, one profiles line
cp "$R/.gitignore" "$TMP/fork.before"; ( cd "$R" && git add -A && git -c user.email=a@b -c user.name=n commit -qm moved )
bash "$SCRIPT" "$R" --apply >/dev/null
cmp -s "$R/.gitignore" "$TMP/fork.before" || fail "second --apply changed .gitignore"
[[ "$(grep -c '^!\.context/profiles/$' "$R/.gitignore")" == 1 ]] || fail "second --apply duplicated the whitelist"

# 4c. --help prints the usage and exits 0
out="$(bash "$SCRIPT" --help)"; rc=$?
[[ $rc -eq 0 && "$out" == *"--include-deploy"* ]] || fail "--help: rc=$rc out=$out"

# 4d. uncommitted .gitignore refuses --apply
R="$TMP/gidirty"; mkrepo "$R"; echo '# edit' >> "$R/.gitignore"
if bash "$SCRIPT" "$R" --apply >/dev/null 2>&1; then fail "dirty .gitignore was not refused"; fi
[[ -f "$R/.context/artifact-style.md" ]] || fail "dirty .gitignore refusal still moved a file"

# 5. a dirty profile refuses the whole project
R="$TMP/dirty"; mkrepo "$R"; echo edit >> "$R/.context/testing-profile.md"
if bash "$SCRIPT" "$R" --apply >/dev/null 2>&1; then fail "dirty profile was not refused"; fi
[[ -f "$R/.context/artifact-style.md" && ! -e "$R/.context/profiles" ]] || fail "refusal still moved something"

# 6. an untracked profile moves with plain mv and a note
R="$TMP/untracked"; mkdir -p "$R/.context"; ( cd "$R" && git init -q && echo u > .context/ui-contract.md )
out="$(bash "$SCRIPT" "$R" --apply)"
[[ -f "$R/.context/profiles/ui-contract.md" && ! -e "$R/.context/ui-contract.md" ]] || fail "untracked profile not moved"
[[ "$out" == *"UNTRACKED-MOVED .context/profiles/ui-contract.md (now versionable: check for secrets, then git add)"* ]] || fail "plain mv not noted: $out"
( cd "$R" && git ls-files --error-unmatch .context/profiles/ui-contract.md >/dev/null 2>&1 ) && fail "script git-added an untracked file"
[[ "$(bash "$SCRIPT" "$TMP/apply" --apply 2>&1)" != *UNTRACKED-MOVED* ]] || fail "a tracked move printed UNTRACKED-MOVED"

if [[ $failures -gt 0 ]]; then printf '%d failure(s)\n' "$failures"; exit 1; fi
echo "OK — migrate-profiles: dry-run inert, apply git-mv + one whitelist rewrite, dirty refused, deploy gated, BP block untouched"
