#!/usr/bin/env bash
# test-symlink-checker.sh — the symlink-checker agent's scan snippet must classify
# relative and absolute symlinks correctly, in both healthy and dangling form.
#
# Regression (backlog BL-031, reproduced 2026-07-25): the snippet did
#   target=$(readlink "$link"); if [ ! -e "$target" ]
# `readlink` without -f returns the target exactly as written, so a RELATIVE target was
# resolved against the caller's cwd instead of the link's own directory. Every healthy
# relative symlink was reported BROKEN -> [LK1] CRITICAL. install.sh writes absolute
# links, so aidex's own install never tripped it — it only misfired on hand-made links,
# which is precisely what this agent exists to judge.
#
# The snippet is EXTRACTED from the shipped agent file, never copied here: on 2026-07-24
# two repo tests were found silently dead because they hard-coded values another file
# owned. A copy would pass while the shipped prompt stayed broken.
#
# Run with: bash tests/test-symlink-checker.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
AGENT="$REPO_ROOT/skills/aidex/agents/symlink-checker.md"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

[[ -f "$AGENT" ]] || { echo "FAIL: agent file not found ($AGENT)"; exit 1; }

# --- extract the first ```bash block that scans for symlinks ---
SNIPPET="$(awk '/^```bash$/{inb=1; buf=""; next} /^```$/{if (inb && buf ~ /-type l/) {printf "%s", buf; exit} inb=0} inb{buf = buf $0 "\n"}' "$AGENT")"
[[ -n "$SNIPPET" ]] || { echo "FAIL: could not extract a '-type l' bash block from $AGENT"; exit 1; }

# The snippet must not test the raw readlink output — that is the bug itself.
if printf '%s' "$SNIPPET" | grep -qE '\[\s*!\s*-e\s*"\$(target|raw)"\s*\]'; then
  fail "snippet still tests the raw readlink target; relative links will misfire"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.claude/skills" "$TMP/real"
echo "content" > "$TMP/real/target.md"
mkdir -p "$TMP/real/adir"

# (1) healthy RELATIVE symlink — the regression case
ln -s "../../real/target.md"  "$TMP/.claude/skills/rel-ok.md"
# (2) healthy ABSOLUTE symlink — what install.sh writes
ln -s "$TMP/real/target.md"   "$TMP/.claude/skills/abs-ok.md"
# (3) healthy RELATIVE symlink to a directory — the common skill case
ln -s "../../real/adir"       "$TMP/.claude/skills/rel-dir-ok"
# (4) dangling RELATIVE symlink — must still be caught
ln -s "../../real/gone.md"    "$TMP/.claude/skills/rel-broken.md"
# (5) dangling ABSOLUTE symlink — must still be caught
ln -s "$TMP/real/gone-abs.md" "$TMP/.claude/skills/abs-broken.md"

# Run the snippet from a cwd that is NOT the fixture, so a cwd-dependent resolution
# cannot accidentally succeed. This is the condition the original bug needed.
out="$(cd "$REPO_ROOT" && SCAN="$TMP/.claude" bash -c "$SNIPPET" 2>&1)"

expect_ok()     { printf '%s' "$out" | grep -q "^OK: .*$1"     || fail "$2 — expected OK, got: $(printf '%s' "$out" | grep "$1" || echo '<no line>')"; }
expect_broken() { printf '%s' "$out" | grep -q "^BROKEN: .*$1" || fail "$2 — expected BROKEN, got: $(printf '%s' "$out" | grep "$1" || echo '<no line>')"; }

expect_ok     "rel-ok.md"      "(1) healthy relative symlink"
expect_ok     "abs-ok.md"      "(2) healthy absolute symlink"
expect_ok     "rel-dir-ok"     "(3) healthy relative symlink to a directory"
expect_broken "rel-broken.md"  "(4) dangling relative symlink"
expect_broken "abs-broken.md"  "(5) dangling absolute symlink"

# Every link must be classified exactly once.
n="$(printf '%s\n' "$out" | grep -cE '^(OK|BROKEN): ')"
[[ "$n" -eq 5 ]] || fail "expected 5 classified links, got $n:\n$out"

# LK2 needs an ABSOLUTE resolved target to judge "unexpected location"; a raw relative
# path would make a legitimate ~/.myskills/ link read as unexpected.
printf '%s' "$out" | grep "^OK: .*rel-ok.md" | grep -q -- "-> /" \
  || fail "OK line for a relative link does not report an absolute resolved target"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — snippet classifies relative/absolute × healthy/dangling correctly (5/5), resolves absolute for LK2"
