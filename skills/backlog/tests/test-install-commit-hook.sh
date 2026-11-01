#!/usr/bin/env bash
# test-install-commit-hook.sh — the post-commit hook lands where git actually reads hooks from
# (backlog-c17): the hooksPath directory when core.hooksPath is set, the common hooks
# directory from a linked worktree. `--git-dir`/hooks was neither.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
G() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

echo "install-commit-hook.sh:"
R="$TMP/repo"; git init -q "$R"; ( cd "$R" && G commit -q --allow-empty -m init )
( cd "$R" && git config core.hooksPath .githooks && bash "$SCRIPTS/install-commit-hook.sh" >/dev/null 2>&1 )
[[ -x "$R/.githooks/post-commit" && ! -e "$R/.git/hooks/post-commit" ]] \
  && ok "hooksPath: the hook goes to the directory git reads" || bad "hooksPath: $(ls "$R/.githooks" "$R/.git/hooks" 2>&1 | tr '\n' ' ')"
( cd "$R" && bash "$SCRIPTS/install-commit-hook.sh" --remove >/dev/null 2>&1 )
[[ -f "$R/.githooks/post-commit" ]] && ! grep -q 'aidex commit-trailer' "$R/.githooks/post-commit" \
  && ok "hooksPath: --remove strips the block from the same directory" || bad "hooksPath: --remove left the block or the file"

R2="$TMP/repo2"; git init -q "$R2"; ( cd "$R2" && G commit -q --allow-empty -m init && G worktree add -q "$TMP/wt" -b wtb )
( cd "$TMP/wt" && bash "$SCRIPTS/install-commit-hook.sh" >/dev/null 2>&1 ); RC=$?
[[ $RC -eq 0 && -x "$R2/.git/hooks/post-commit" ]] \
  && ok "linked worktree: the hook is written to the common hooks directory" || bad "worktree: rc=$RC $(ls "$R2/.git/hooks" | tr '\n' ' ')"

# BL-893: when the baked path is gone, the fallback finds the cache of either profile
# (~/.claude-work as well as ~/.claude), from a plain terminal with no CLAUDE_CONFIG_DIR.
R3="$TMP/repo3"; git init -q "$R3"; ( cd "$R3" && G commit -q --allow-empty -m init )
GONE="$TMP/gone/scripts"; mkdir -p "$GONE"; cp "$SCRIPTS/install-commit-hook.sh" "$GONE/"
( cd "$R3" && bash "$GONE/install-commit-hook.sh" >/dev/null 2>&1 ); rm -rf "$TMP/gone"
H="$TMP/home"; C="$H/.claude-work/plugins/cache/m/aidex/9.9.9/skills/backlog/scripts"; mkdir -p "$C"
printf '#!/bin/sh\ntouch "%s"\n' "$TMP/harvested" > "$C/harvest-commit.sh"; chmod +x "$C/harvest-commit.sh"
( cd "$R3" && HOME="$H" G commit -q --allow-empty -m two )
[[ -e "$TMP/harvested" ]] && ok "fallback: a ~/.claude-work plugin cache is found" \
  || bad "fallback: the work profile's cache was not found"

# The original side of that glob: a cache only under ~/.claude is still found, and with both
# profiles cached the newest copy runs (ls -t), here the ~/.claude one.
H2="$TMP/home2"; P="$H2/.claude/plugins/cache/m/aidex/9.9.9/skills/backlog/scripts"; mkdir -p "$P"
printf '#!/bin/sh\ntouch "%s"\n' "$TMP/personal" > "$P/harvest-commit.sh"; chmod +x "$P/harvest-commit.sh"
( cd "$R3" && HOME="$H2" G commit -q --allow-empty -m three )
[[ -e "$TMP/personal" ]] && ok "fallback: a ~/.claude plugin cache is still found" \
  || bad "fallback: the ~/.claude cache was not found"
rm -f "$TMP/personal"; W="$H2/.claude-work/plugins/cache/m/aidex/9.9.8/skills/backlog/scripts"; mkdir -p "$W"
printf '#!/bin/sh\ntouch "%s"\n' "$TMP/work" > "$W/harvest-commit.sh"; chmod +x "$W/harvest-commit.sh"
touch -t 202601010000 "$W/harvest-commit.sh"; touch -t 202602010000 "$P/harvest-commit.sh"
( cd "$R3" && HOME="$H2" G commit -q --allow-empty -m four )
[[ -e "$TMP/personal" && ! -e "$TMP/work" ]] && ok "fallback: with both profiles cached the newest copy runs" \
  || bad "fallback: newest-copy pick wrong (personal=$([[ -e "$TMP/personal" ]] && echo y) work=$([[ -e "$TMP/work" ]] && echo y))"

# A repo wired before the glob widened is upgraded by re-running the installer: the aidex
# block is replaced, the rest of the hook kept, and a third run changes nothing.
R4="$TMP/repo4"; git init -q "$R4"; HK="$R4/.git/hooks/post-commit"; mkdir -p "$R4/.git/hooks"
{ printf '#!/usr/bin/env bash\necho mine\n'
  printf '%s\n' '# >>> aidex commit-trailer harvester (D-09) >>>' \
    'h=/gone/harvest-commit.sh; [ -x "$h" ] || h=$(ls -t "$HOME"/.claude/plugins/cache/*/aidex/*/skills/backlog/scripts/harvest-commit.sh 2>/dev/null | sed -n 1p); [ -n "$h" ] && "$h" >/dev/null 2>&1 || true' \
    '# <<< aidex commit-trailer harvester <<<'; } > "$HK"; chmod +x "$HK"
( cd "$R4" && bash "$SCRIPTS/install-commit-hook.sh" >/dev/null 2>&1 )
grep -qF '.claude*/plugins/cache' "$HK" && ! grep -qF '/gone/' "$HK" && grep -qx 'echo mine' "$HK" \
  && [[ "$(grep -cF 'aidex commit-trailer harvester (D-09)' "$HK")" == 1 ]] \
  && ok "re-install: an old aidex block is replaced, the user's lines kept" || bad "re-install: $(cat "$HK")"
cp "$HK" "$TMP/hk.before"; ( cd "$R4" && bash "$SCRIPTS/install-commit-hook.sh" >/dev/null 2>&1 )
cmp -s "$HK" "$TMP/hk.before" && ok "re-install: a current block is left byte-identical" || bad "re-install: a current block changed"

echo; [[ $FAIL -eq 0 ]] && { echo "OK — install-commit-hook: $PASS cells"; exit 0; }; echo "$FAIL failure(s)"; exit 1
