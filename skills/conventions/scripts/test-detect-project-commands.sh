#!/usr/bin/env bash
# test-detect-project-commands.sh — smoke tests for detect-project-commands.sh.
#
# Covers (found via field-testing against a real project, 2026-07-01):
#   - flat .claude/commands/*.md detection (review, commit)
#   - NAMESPACED .claude/commands/<subdir>/<name>.md detection (release), which
#     a maxdepth-1 search misses entirely — this is the regression this test locks in
#   - cache reuse across two runs
#
# Run with: bash skills/conventions/scripts/test-detect-project-commands.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DETECTOR="$SCRIPT_DIR/detect-project-commands.sh"
# A private copy: the detector writes its cache into the project, and a shared in-repo
# fixture made concurrent runs trample each other's cache (c42).
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp -R "$SCRIPT_DIR/fixtures/detect-commands" "$TMP/fixture"
FIXTURE="$TMP/fixture"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

rm -f "$FIXTURE/.claude/.aidex-detected-commands.json"

bash "$DETECTOR" --project "$FIXTURE" >/dev/null
out1="$(cat "$FIXTURE/.claude/.aidex-detected-commands.json")"

review="$(printf '%s' "$out1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("review_command"))')"
commit="$(printf '%s' "$out1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("commit_command"))')"
release="$(printf '%s' "$out1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("release_command"))')"

[[ "$review" == "/code-review" ]] || fail "review_command: expected /code-review, got $review"
[[ "$commit" == "/commit" ]] || fail "commit_command: expected /commit, got $commit"
[[ "$release" == "/version:release" ]] || fail "release_command (namespaced): expected /version:release, got $release — namespaced .claude/commands/<subdir>/<name>.md detection regressed"

wt_up="$(printf '%s' "$out1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("worktree_up_command"))')"
wt_down="$(printf '%s' "$out1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("worktree_down_command"))')"
[[ "$wt_up" == "./worktree-up.sh <slug>" ]] || fail "worktree_up_command: expected ./worktree-up.sh <slug> (from .context/worktrees front-matter), got $wt_up"
[[ "$wt_down" == "./worktree-down.sh <slug>" ]] || fail "worktree_down_command: expected ./worktree-down.sh <slug>, got $wt_down"

# Deterministic: edit a field in the cache; a second run must print the edited value (read from the
# cache, not re-scanned) and leave the file as edited.
CACHE="$FIXTURE/.claude/.aidex-detected-commands.json"
python3 - "$CACHE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["review_command"] = "/cache-marker"
json.dump(d, open(sys.argv[1], "w"))
PY
out2="$(bash "$DETECTOR" --project "$FIXTURE")"
grep -qF 'review_command: /cache-marker' <<<"$out2" || fail "cache reuse: a second run did not print the cached value: $out2"
grep -qF '/cache-marker' "$CACHE" || fail "cache reuse: the second run rewrote the cache"

# A nonexistent --project is refused; it used to leave ROOT empty and scan /.
if bash "$DETECTOR" --project "$TMP/does-not-exist" >/dev/null 2>"$TMP/err"; then
  fail "nonexistent --project exited 0"
fi
grep -q "project directory not found" "$TMP/err" || fail "nonexistent --project: the script gave no clear error (it kept going with an empty ROOT): $(cat "$TMP/err")"

# The worktree fallback promises an EXECUTABLE worktree-up*.sh: a plain file is no command.
P2="$TMP/noexec"; mkdir -p "$P2"
printf '#!/bin/sh\n' > "$P2/worktree-up.sh"; printf '#!/bin/sh\n' > "$P2/worktree-down.sh"; chmod +x "$P2/worktree-down.sh"
bash "$DETECTOR" --project "$P2" >/dev/null
out3="$(cat "$P2/.claude/.aidex-detected-commands.json")"
up="$(printf '%s' "$out3" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("worktree_up_command"))')"
down="$(printf '%s' "$out3" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("worktree_down_command"))')"
[[ "$up" == "None" ]] || fail "non-executable worktree-up.sh was detected as a command: $up"
[[ "$down" == "./worktree-down.sh" ]] || fail "executable worktree-down.sh not detected: $down"

# Only a MATCHED pair of surrounding quotes is stripped from a front-matter command: an
# unquoted value ending in a quote keeps it, a quoted one keeps its inner quotes (BL-927).
P3="$TMP/quotes"; mkdir -p "$P3/.context/worktrees"
printf -- '---\nworktree_up: worktree.sh up "<slug>"\nworktree_down: "worktree.sh down \x27<slug>\x27"\n---\n' > "$P3/.context/worktrees/00-index.md"
bash "$DETECTOR" --project "$P3" >/dev/null
out4="$(cat "$P3/.claude/.aidex-detected-commands.json")"
up="$(printf '%s' "$out4" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("worktree_up_command"))')"
down="$(printf '%s' "$out4" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("worktree_down_command"))')"
[[ "$up" == 'worktree.sh up "<slug>"' ]] || fail "unquoted worktree_up lost its closing quote: $up"
[[ "$down" == "worktree.sh down '<slug>'" ]] || fail "quoted worktree_down: only the surrounding pair goes: $down"
printf -- '---\nworktree_up: "worktree.sh up <slug>\n---\n' > "$P3/.context/worktrees/00-index.md"; rm -f "$P3/.claude/.aidex-detected-commands.json"
bash "$DETECTOR" --project "$P3" >/dev/null
up="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("worktree_up_command"))' "$P3/.claude/.aidex-detected-commands.json")"
[[ "$up" == '"worktree.sh up <slug>' ]] || fail "a lone leading quote on worktree_up was stripped: $up"
printf -- '---\nworktree_up: "worktree.sh up <slug>"  \r\n---\n' > "$P3/.context/worktrees/00-index.md"; rm -f "$P3/.claude/.aidex-detected-commands.json"
bash "$DETECTOR" --project "$P3" >/dev/null
up="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("worktree_up_command"))' "$P3/.claude/.aidex-detected-commands.json")"
[[ "$up" == 'worktree.sh up <slug>' ]] || fail "trailing whitespace and a CR after a matched pair kept the quotes: $up"
# The same pair rule as profile_field (BL-931): a single-quoted pair goes too; a pair whose
# quote kind occurs inside is two quoted words, kept whole; a blank key with a comment is no
# command, so the executable worktree-down.sh fallback still answers.
printf -- '---\nworktree_up: \x27worktree.sh up <slug>\x27\nworktree_down: # fill in\n---\n' > "$P3/.context/worktrees/00-index.md"; rm -f "$P3/.claude/.aidex-detected-commands.json"
printf '#!/usr/bin/env bash\n' > "$P3/worktree-down.sh"; chmod +x "$P3/worktree-down.sh"
bash "$DETECTOR" --project "$P3" >/dev/null
up="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("worktree_up_command"))' "$P3/.claude/.aidex-detected-commands.json")"
down="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("worktree_down_command"))' "$P3/.claude/.aidex-detected-commands.json")"
[[ "$up" == 'worktree.sh up <slug>' ]] || fail "a single-quoted worktree_up kept its quotes: $up"
[[ "$down" == './worktree-down.sh' ]] || fail "a blank worktree_down with a comment was read as a command: $down"
printf -- '---\nworktree_up: "worktree.sh" "up <slug>"\n---\n' > "$P3/.context/worktrees/00-index.md"; rm -f "$P3/.claude/.aidex-detected-commands.json"
bash "$DETECTOR" --project "$P3" >/dev/null
up="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("worktree_up_command"))' "$P3/.claude/.aidex-detected-commands.json")"
[[ "$up" == '"worktree.sh" "up <slug>"' ]] || fail "two quoted words on worktree_up lost the outer pair: $up"
# an escaped quote inside does not count (the pair goes, the escape stays); a blank key whose
# comment follows a tab is still blank; `#` then a non-space is a value; a trailing ` #` is the
# command's and stays.
printf -- '---\nworktree_up: "worktree.sh up \\"<slug>\\""\nworktree_down: \t# fill in\n---\n' > "$P3/.context/worktrees/00-index.md"; rm -f "$P3/.claude/.aidex-detected-commands.json"
bash "$DETECTOR" --project "$P3" >/dev/null
up="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("worktree_up_command"))' "$P3/.claude/.aidex-detected-commands.json")"
down="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("worktree_down_command"))' "$P3/.claude/.aidex-detected-commands.json")"
[[ "$up" == 'worktree.sh up \"<slug>\"' ]] || fail "an escaped quote inside worktree_up kept the outer pair: $up"
[[ "$down" == './worktree-down.sh' ]] || fail "a blank worktree_down with a tab before its comment was read as a command: $down"
printf -- '---\nworktree_up: #up.sh\nworktree_down: worktree.sh down <slug> # note\n---\n' > "$P3/.context/worktrees/00-index.md"; rm -f "$P3/.claude/.aidex-detected-commands.json"
bash "$DETECTOR" --project "$P3" >/dev/null
up="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("worktree_up_command"))' "$P3/.claude/.aidex-detected-commands.json")"
down="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("worktree_down_command"))' "$P3/.claude/.aidex-detected-commands.json")"
[[ "$up" == '#up.sh' ]] || fail "'#' followed by a non-space on worktree_up was read as a comment: $up"
[[ "$down" == 'worktree.sh down <slug> # note' ]] || fail "a trailing ' #' on worktree_down was stripped: $down"
# an escaped '' inside a single-quoted pair does not count either; a lone `#` is a blank key's
# comment; a quoted "#tag" is a value; a value that is one quote is kept.
printf -- '---\nworktree_up: \x27worktree.sh up \x27\x27<slug>\x27\x27\x27\nworktree_down: #\n---\n' > "$P3/.context/worktrees/00-index.md"; rm -f "$P3/.claude/.aidex-detected-commands.json"
bash "$DETECTOR" --project "$P3" >/dev/null
up="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("worktree_up_command"))' "$P3/.claude/.aidex-detected-commands.json")"
down="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("worktree_down_command"))' "$P3/.claude/.aidex-detected-commands.json")"
[[ "$up" == "worktree.sh up ''<slug>''" ]] || fail "an escaped '' inside a single-quoted worktree_up kept the outer pair: $up"
[[ "$down" == './worktree-down.sh' ]] || fail "a lone '#' on worktree_down was read as a command: $down"
printf -- '---\nworktree_up: "#up.sh"\nworktree_down: "\n---\n' > "$P3/.context/worktrees/00-index.md"; rm -f "$P3/.claude/.aidex-detected-commands.json"
bash "$DETECTOR" --project "$P3" >/dev/null
up="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("worktree_up_command"))' "$P3/.claude/.aidex-detected-commands.json")"
down="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("worktree_down_command"))' "$P3/.claude/.aidex-detected-commands.json")"
[[ "$up" == '#up.sh' ]] || fail "a quoted '#up.sh' on worktree_up was not read as a value: $up"
[[ "$down" == '"' ]] || fail "a worktree_down that is one quote was not kept: $down"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — flat + namespaced command detection, cache reuse"
