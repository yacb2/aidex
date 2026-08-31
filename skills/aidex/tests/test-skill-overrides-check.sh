#!/usr/bin/env bash
# test-skill-overrides-check.sh — a skillOverrides key that names nothing is inert, and
# nothing else reports it: the JSON is valid and the skill is real, just not under that
# id. Plugin skills register namespaced (`document-skills:docx`), so a key written
# before that namespacing silences nothing and the skill loads at full cost.
#
# Fully fixtured: no assertion reads the machine's real ~/.claude, or the cell would
# pass or fail on whichever plugins happen to be installed today.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHECK="$DIR/../scripts/check-skill-overrides.py"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkskill() { mkdir -p "$1"; printf -- '---\nname: %s\n---\nbody\n' "$(basename "$1")" > "$1/SKILL.md"; }

# personal store
mkskill "$TMP/skills/aidex-dash"
mkskill "$TMP/skills/theme-factory"
# a second store, the shape of a per-project install pointing at ~/.myskills
mkskill "$TMP/extra/skill-trigger-eval"
# plugin cache: <marketplace>/<plugin>/<version>/skills/<skill>
mkskill "$TMP/cache/anthropic/document-skills/v1/skills/docx"
mkskill "$TMP/cache/anthropic/document-skills/v1/skills/theme-factory"
mkskill "$TMP/cache/anthropic/off-plugin/v1/skills/never-loaded"
# the .claude/skills layout some plugins use instead
mkskill "$TMP/cache/official/vercel/v1/.claude/skills/release"

settings() { printf '%s\n' "$1" > "$TMP/settings.json"; }
run() { python3 "$CHECK" --settings "$TMP/settings.json" --skills-root "$TMP/skills" \
          --skills-dir "$TMP/extra" --plugin-cache "$TMP/cache" "$@"; }

ENABLED='"enabledPlugins": {"document-skills@anthropic": true, "vercel@official": true, "off-plugin@anthropic": false}'

# 1 · every key resolves -> exit 0, and the run says how much it looked at
settings "{$ENABLED, \"skillOverrides\": {\"aidex-dash\": \"off\", \"document-skills:docx\": \"off\", \"skill-trigger-eval\": \"name-only\", \"vercel:release\": \"off\"}}"
OUT="$(run)"; RC=$?
[[ $RC -eq 0 ]] && ok "1 every key resolving exits 0" || bad "1 rc=$RC: $OUT"
grep -q 'OK — every key resolves' <<<"$OUT" && ok "1 says so" || bad "1 verdict: $OUT"
# A green gate must say what it saw, or a checker that enumerated nothing looks the same.
grep -qE 'checked 4 skillOverrides key\(s\) against [0-9]+ personal \+ [0-9]+ plugin' <<<"$OUT" \
  && ok "1 prints the counts it processed" || bad "1 no counts: $OUT"
grep -q 'vercel:release' <<<"$OUT" && bad "1 a resolving key was reported" || ok "1 the .claude/skills plugin layout is found"

# 2 · a bare plugin-skill name is UNRESOLVED, and the suggestion names the real id
settings "{$ENABLED, \"skillOverrides\": {\"docx\": \"name-only\"}}"
OUT="$(run)"; RC=$?
[[ $RC -eq 1 ]] && ok "2 a bare plugin-skill name fails the check" || bad "2 rc=$RC: $OUT"
grep -q 'UNRESOLVED  docx — did you mean `document-skills:docx`?' <<<"$OUT" \
  && ok "2 the suggestion names the namespaced id" || bad "2 suggestion: $OUT"

# 3 · a key naming nothing at all says so, with no invented suggestion
settings "{$ENABLED, \"skillOverrides\": {\"ghost-skill\": \"off\"}}"
OUT="$(run)"; RC=$?
[[ $RC -eq 1 ]] && grep -q 'ghost-skill — no skill of that name is installed' <<<"$OUT" \
  && ok "3 an absent skill is reported without a suggestion" || bad "3 rc=$RC: $OUT"

# 4 · a DISABLED plugin's skill does not resolve — an override on it is as inert as a
#     misspelt one, which is the whole point of the check
settings "{$ENABLED, \"skillOverrides\": {\"off-plugin:never-loaded\": \"off\"}}"
OUT="$(run)"; RC=$?
[[ $RC -eq 1 ]] && ok "4 a disabled plugin's skill does not resolve" || bad "4 rc=$RC: $OUT"

# 5 · SHADOWED: the key resolves to the personal skill, and a namespaced twin exists
#     that it does not touch. Valid, so not a failure — but not silent either.
settings "{$ENABLED, \"skillOverrides\": {\"theme-factory\": \"name-only\"}}"
OUT="$(run)"; RC=$?
[[ $RC -eq 0 ]] && ok "5 a shadowed key still resolves (exit 0)" || bad "5 rc=$RC: $OUT"
grep -q 'SHADOWED    theme-factory' <<<"$OUT" \
  && ok "5 the untouched namespaced twin is reported" || bad "5 not reported: $OUT"

# 6 · no overrides at all is not a silent pass
settings "{$ENABLED, \"skillOverrides\": {}}"
OUT="$(run)"; RC=$?
[[ $RC -eq 0 ]] && grep -q 'no skillOverrides to check' <<<"$OUT" \
  && ok "6 an empty override set says it checked nothing" || bad "6 rc=$RC: $OUT"

# 7 · --json carries the same verdict, and an unreadable settings file is exit 2
settings "{$ENABLED, \"skillOverrides\": {\"docx\": \"off\", \"theme-factory\": \"off\"}}"
J="$(run --json)"
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["checked"]==2; assert d["unresolved"][0]["suggestion"]=="document-skills:docx"; assert d["shadowed"][0]["key"]=="theme-factory"' "$J" \
  && ok "7 --json carries the unresolved and shadowed keys" || bad "7 json: $J"
python3 "$CHECK" --settings "$TMP/nope.json" >/dev/null 2>&1; [[ $? -eq 2 ]] \
  && ok "7 an unreadable settings file is exit 2, never a silent pass" || bad "7 missing settings not exit 2"

echo
[[ $FAIL -eq 0 ]] && { echo "OK — skill-overrides check: $PASS cells"; exit 0; }
echo "$FAIL failure(s), $PASS ok"; exit 1
