#!/usr/bin/env bash
# test-discovery-census.sh — every test file on disk is either discovered by
# run-all.sh or excluded by name, with a reason. Nothing is invisible by accident.
#
# run-all.sh's own header records this failing three times: `scripts/` globs that
# matched `test_*` only hid 17 hyphenated tests, `hooks/` was never a discovery
# root and hid both hook tests, and before that `skills/*/scripts/` was not walked
# at all and an over-maximum SKILL.md reached a commit with the suite green
# (BL-113). Each was fixed by adding one more glob. A fourth patch with no guard
# invites a fifth, so this is the guard.
#
# The asymmetry that makes it work: `find` enumerates by NAME across the whole
# tree, while run-all.sh enumerates by PATH SHAPE. The census is broader than the
# runner by construction, so a file the runner's globs miss shows up here as a
# difference rather than as silence. It asks run-all.sh what it found
# (`--list`) instead of restating the globs — a second copy of them would drift,
# which is the very defect being guarded.
#
# Adding a test in a new location is meant to fail this once. The fix is a glob in
# run-all.sh, not a line in EXCLUDED — that list is for files that are not tests.
#
# Run with: bash tests/test-discovery-census.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# Not tests, despite the name. Each line is `<path> | <why>`.
EXCLUDED="\
hooks/eval/test-router-fallback.sh | the RETIRED aidex-router's eval harness — the hook is unwired and its replay came out p=0.72
skills/worktree/scripts/test-db-preflight.sh | a PRODUCTION script that preflights the TEST database, which is why its name starts that way; its own test is test-test-db-preflight.sh"

# The widest set the runner can discover.
discovered="$(RUN_DOCKER_TESTS=1 bash tests/run-all.sh --list | sort)"
[ -n "$discovered" ] || { echo "FAIL: run-all.sh --list returned nothing"; exit 1; }

# Candidates are filtered through git's own ignore rules rather than a hand-list of
# directories. Measured 2026-09-07: a second session put a git worktree at
# .claude/worktrees/<slug>/ — INSIDE this repo — and a hand-rolled exclusion list
# walked straight into it, turning 148 files into 295 and failing on a whole second
# checkout of this very repo. `.claude/`, `.context/`, `.dt/` and `_tmp/` are all
# gitignored (see CLAUDE.md), so asking git is both shorter and correct for the
# next ignored tree nobody has invented yet. It is NOT `git ls-files`: a test you
# just wrote and have not staged must still be seen.
candidates="$(find . -type f \
  \( -name 'test-*.sh' -o -name 'test_*.sh' -o -name 'test-*.py' -o -name 'test_*.py' \) \
  -not -path './.git/*' | sed 's|^\./||' | sort)"
ignored="$(printf '%s\n' "$candidates" | git check-ignore --stdin 2>/dev/null | sort)"
found="$(comm -23 <(printf '%s\n' "$candidates") <(printf '%s\n' "$ignored"))"
found_n="$(printf '%s\n' "$found" | grep -c .)"
[ "$found_n" -gt 0 ] || { echo "FAIL: found zero test files on disk — the census scanned nothing"; exit 1; }

# A `git check-ignore` that silently matched nothing would put every ignored tree
# back in scope, which is the failure this filter was added for.
ignored_n="$(printf '%s\n' "$ignored" | grep -c .)"
printf 'census: %s candidate files, %s dropped as gitignored\n' \
  "$(printf '%s\n' "$candidates" | grep -c .)" "$ignored_n"

printf 'census: %s test files on disk, %s discovered by run-all.sh --list\n' \
  "$found_n" "$(printf '%s\n' "$discovered" | grep -c .)"

# Materialised, because the lookups below use `grep -q`, which exits at the FIRST
# match and closes its pipe. With `set -o pipefail` a writer still filling that
# pipe takes SIGPIPE and the pipeline reports 141 for a match that DID happen —
# a load-dependent false negative, measured today at 1 in 840 in run-all.sh's
# parity selector. `grep -q <pattern> <file>` has no pipe and no race.
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
printf '%s\n' "$EXCLUDED" | sed 's/ *|.*//' | sort > "$TMPD/excluded"
printf '%s\n' "$discovered" > "$TMPD/discovered"
excluded_paths="$(cat "$TMPD/excluded")"

# 1. Nothing on disk is invisible.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -qxF "$f" "$TMPD/discovered" && continue
  grep -qxF "$f" "$TMPD/excluded"   && continue
  fail "$f is on disk but no run-all.sh glob discovers it — add a glob, do not add an exclusion"
done <<< "$found"

# 2. The exclusion list does not rot. A stale entry silently widens next time.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || fail "EXCLUDED names $f, which is not on disk — drop the line"
  grep -qxF "$f" "$TMPD/discovered" \
    && fail "EXCLUDED names $f, but run-all.sh discovers it — the exclusion is a lie"
done <<< "$excluded_paths"

if [ "$failures" -eq 0 ]; then
  printf 'OK — every test file is discovered or excluded by name (%s excluded)\n' \
    "$(printf '%s\n' "$excluded_paths" | grep -c .)"
  exit 0
fi
exit 1
