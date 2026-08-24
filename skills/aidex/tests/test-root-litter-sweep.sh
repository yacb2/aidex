#!/usr/bin/env bash
# test-root-litter-sweep.sh — BL-224: a fixture workspace with one instance of each
# litter category is fully reported, and a clean one reports nothing.
#
# The negative half is the point. Four of the five categories fire on names and shapes
# that a real workspace legitimately contains (a project IS a git repo; a project's own
# `_tmp/` IS canonical scratch), so a scanner that only proves it can find things is
# indistinguishable from one that flags everything.

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)/root-litter-sweep.py"
FAILURES=0
fail() { printf 'FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$*"; }

WS="$(mktemp -d)"
trap 'rm -rf "$WS"' EXIT

# --- one instance of each of the five categories --------------------------------
# 1. in-project-backups: the regression guard for the fix in 1627663
mkdir -p "$WS/alpha_ws/.aidex-backups" && : > "$WS/alpha_ws/.aidex-backups/old.tar"
mkdir -p "$WS/alpha_ws/.context"
# 2. holding-folder
mkdir -p "$WS/_toDelete" && : > "$WS/_toDelete/whatever"
# 3. loose-file at the workspace root
printf 'notes\n' > "$WS/_PLAN_something.md"
# 4. stray-repo: a git repo with no project marker
mkdir -p "$WS/some-clone/.git" && : > "$WS/some-clone/README.md"
# 5. dead-permission: a Bash permission naming a command that is not installed
mkdir -p "$WS/beta_ws/.claude"
cat > "$WS/beta_ws/.claude/settings.local.json" <<'EOF'
{"permissions": {"allow": ["Bash(definitely-not-a-real-command-xyz:*)", "Bash(ls:*)"]}}
EOF
: > "$WS/beta_ws/CLAUDE.md"

OUT="$(python3 "$SCRIPT" --root "$WS" 2>&1)"; RC=$?
[[ $RC -eq 0 ]] || fail "expected exit 0 (census, not a gate), got $RC"

for cat in in-project-backups holding-folder loose-file stray-repo dead-permission; do
  grep -q "^$cat (" <<<"$OUT" || fail "category '$cat' was not reported: $OUT"
done
pass "all five litter categories are reported from one fixture workspace"

# Ownership must distinguish "aidex left this" from "you left this".
grep -q '\[aidex  *\].*\.aidex-backups' <<<"$OUT" \
  || fail "in-project backups was not attributed to aidex: $OUT"
grep -q '\[foreign\].*some-clone' <<<"$OUT" \
  || fail "a stray clone was not attributed as foreign: $OUT"
pass "findings are classified aidex vs foreign"

grep -q 'definitely-not-a-real-command-xyz' <<<"$OUT" \
  || fail "the uninstalled command was not named in the dead-permission finding"
grep -q 'Bash(ls' <<<"$OUT" && fail "an INSTALLED command was reported as a dead permission"
pass "dead-permission fires on a missing command and not on an installed one"

grep -qi 'read-only' <<<"$OUT" || fail "the report does not say it changed nothing"
# Nothing may be removed: the fixture must survive the sweep intact.
for p in "$WS/_toDelete/whatever" "$WS/_PLAN_something.md" "$WS/alpha_ws/.aidex-backups/old.tar" \
         "$WS/some-clone/README.md" "$WS/beta_ws/.claude/settings.local.json"; do
  [[ -e "$p" ]] || fail "the sweep deleted $p — it must report and offer, never delete"
done
pass "read-only: every fixture file survived the sweep"

# --- negative cells: a legitimate workspace reports nothing -----------------------
CLEAN="$(mktemp -d)"
mkdir -p "$CLEAN/gamma_ws/.git" "$CLEAN/gamma_ws/.context" "$CLEAN/gamma_ws/_tmp"
: > "$CLEAN/gamma_ws/CLAUDE.md"
: > "$CLEAN/gamma_ws/_tmp/scratch.txt"
mkdir -p "$CLEAN/delta_ws/.claude"
: > "$CLEAN/delta_ws/CLAUDE.md"
echo '{"permissions": {"allow": ["Bash(git:*)"]}}' > "$CLEAN/delta_ws/.claude/settings.json"
: > "$CLEAN/.DS_Store"

OUT2="$(python3 "$SCRIPT" --root "$CLEAN" 2>&1)"; RC2=$?
[[ $RC2 -eq 0 ]] || fail "clean workspace: expected exit 0, got $RC2"
grep -q 'nothing to report' <<<"$OUT2" \
  || fail "a legitimate workspace was flagged — projects are git repos and a project's own _tmp/ is canonical scratch: $OUT2"
pass "a project (git repo + CLAUDE.md), its own _tmp/, and .DS_Store are not litter"
rm -rf "$CLEAN"

# --- --json carries the same findings ---------------------------------------------
J="$WS/out.json"
python3 "$SCRIPT" --root "$WS" --json "$J" >/dev/null 2>&1
python3 - "$J" <<'PY' || fail "--json output is not the same census"
import json, sys
d = json.load(open(sys.argv[1]))
cats = {f["category"] for f in d["findings"]}
expected = {"in-project-backups", "holding-folder", "loose-file", "stray-repo", "dead-permission"}
assert cats == expected, f"{cats} != {expected}"
assert {f["owner"] for f in d["findings"]} <= {"aidex", "foreign"}
PY
pass "--json emits the same five categories with the same ownership vocabulary"

# --- a missing root is an error, not a silent empty census ------------------------
python3 "$SCRIPT" --root "$WS/does-not-exist" >/dev/null 2>&1
[[ $? -eq 2 ]] || fail "a nonexistent root must exit 2, not report an empty clean workspace"
pass "a nonexistent root exits 2 rather than reading as clean"

if [[ $FAILURES -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$FAILURES"
  exit 1
fi
printf '\nOK — root-litter-sweep: 5 categories, ownership, read-only, negatives, json, bad root\n'
