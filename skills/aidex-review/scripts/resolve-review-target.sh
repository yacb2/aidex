#!/usr/bin/env bash
# resolve-review-target.sh — resolve a module / path / whole-app review target to a
# concrete file set, and measure what it would cost to review.
#
# Why this exists, and why it is NOT resolve-review-scope.sh:
#
#   resolve-review-scope.sh answers "which CHANGES am I reviewing?" — it returns a
#   git base ref and a pathspec. Every installed review instrument works that way:
#   /code-review accepts a <path> target but its own scope agent turns it into "build
#   the matching git diff command for it", /simplify reviews "the changed code", and
#   /security-review interpolates `git diff origin/HEAD...`. All three are anchored to
#   a diff.
#
#   This script answers a different question — "which CODE am I reviewing?" — over a
#   module as it stands, with no base ref at all. That is the case nothing covers, and
#   it is why the two resolvers are separate rather than one with a flag: a diff scope
#   is bounded by the change, a module scope is bounded only by the module, and the
#   whole point of this file is to measure that bound before any agent is spawned.
#
# It never returns a silently-empty target: an empty resolution exits 3 rather than
# printing an empty set, so a caller can tell "nothing to review" apart from "wrong
# path". And it has NO default target — a review that silently defaults to the repo
# root is the "checkers lie by omission" failure, one directory wider.
#
# Usage:
#   resolve-review-target.sh <path>              # key=value measurement
#   resolve-review-target.sh --app               # whole repository
#   resolve-review-target.sh --files <path>      # the resolved file list, one per line
#   resolve-review-target.sh --files --app
#
# Exit codes: 0 resolved · 2 usage/bad path · 3 resolved but empty

set -uo pipefail

PRINT_FILES=0
TARGET=""
WHOLE_APP=0
INCLUDE_TESTS=0

usage() {
  cat >&2 <<'USAGE'
usage: resolve-review-target.sh [--files] (<path> | --app)

  <path>   a module, directory, or single file to review as it stands
  --app    the whole repository (see the size classes — this usually must be split)
  --files  print the resolved file list instead of the measurement

There is no default target. Naming what is reviewed is the caller's job.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --files) PRINT_FILES=1; shift ;;
    --app)   WHOLE_APP=1; shift ;;
    --include-tests) INCLUDE_TESTS=1; shift ;;
    -h|--help) usage; exit 2 ;;
    -*) echo "resolve-review-target: unknown flag '$1'" >&2; usage; exit 2 ;;
    *)  if [ -n "$TARGET" ]; then
          echo "resolve-review-target: more than one target given ('$TARGET', '$1')" >&2
          exit 2
        fi
        TARGET="$1"; shift ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [ "$WHOLE_APP" -eq 1 ]; then
  [ -n "$TARGET" ] && { echo "resolve-review-target: --app takes no path" >&2; exit 2; }
  TARGET="$ROOT"
fi

if [ -z "$TARGET" ]; then
  echo "resolve-review-target: no target given. Name a path, or pass --app." >&2
  usage
  exit 2
fi

if [ ! -e "$TARGET" ]; then
  echo "resolve-review-target: '$TARGET' does not exist" >&2
  exit 2
fi

# ── Reviewable file set ───────────────────────────────────────────────────────
# Source files only. Generated, vendored, and archived trees are excluded because a
# finder spending its budget on node_modules is budget that never reached the module.
EXCLUDE_DIRS='node_modules|\.git|dist|build|coverage|__pycache__|\.venv|venv|vendor|_archive|\.next|\.turbo|target|site-packages'
SOURCE_EXT='py|js|jsx|ts|tsx|vue|sh|bash|rb|go|rs|java|kt|php|c|h|cpp|hpp|cs|swift|sql'

collect_files() {
  find "$TARGET" -type f 2>/dev/null \
    | grep -Ev "/($EXCLUDE_DIRS)/" \
    | grep -E "\.($SOURCE_EXT)$" \
    | grep -Ev '\.min\.(js|css)$|\.lock$|-lock\.json$' \
    | LC_ALL=C sort
}

ALL_FILES="$(collect_files)"

# ── Tests are measured apart from source ─────────────────────────────────────
# The size class is a bound on what the FINDERS READ, so it has to be computed on the
# set they actually read. Two things follow, and they are not separable:
#
#   1. The reviewed set excludes tests by default, so the class is not inflated by
#      them. echo_lab's lab_timeline measured 15,394 LOC — oversize, zero finders —
#      against 7,270 LOC of source, which is `large` with 4. A module was refused for
#      being well tested, and its own tests were the largest thing in it.
#   2. `--include-tests` puts them back in the reviewed set AND sizes on the total.
#      Sizing on source while the finders read tests would be a cost bound that does
#      not bound the cost — the same lie by omission this resolver exists to prevent.
#
# Patterns beyond the obvious ones are there because they were measured missing across
# four real repos: `__tests__/` helpers carrying no .test/.spec suffix, and pytest's
# conftest.py. `(^|/)` anchoring keeps `latest.ts`, `protest_utils.py` and `contest.py`
# out — verified against twelve adversarial names, zero false positives.
TEST_RE='(^|/)(test_|tests?/|__tests__/|spec/|e2e/|conftest\.py$)|[._-]test\.|[._-]spec\.'

TEST_FILES="$(printf '%s\n' "$ALL_FILES" | grep -E "$TEST_RE" || true)"
SRC_FILES="$(printf '%s\n' "$ALL_FILES" | grep -Ev "$TEST_RE" || true)"

# A target that is ENTIRELY tests was named deliberately. Excluding them would resolve
# it to zero files and exit 3 — "nothing to review" printed over a directory full of
# code. lab_timeline/tests is 46 files, every one of them a test.
if [ -z "$SRC_FILES" ]; then
  REVIEWED="$ALL_FILES"
  ALL_TESTS=1
elif [ "$INCLUDE_TESTS" -eq 1 ]; then
  REVIEWED="$ALL_FILES"
  ALL_TESTS=0
else
  REVIEWED="$SRC_FILES"
  ALL_TESTS=0
fi

FILES="$REVIEWED"

if [ -z "$FILES" ]; then
  echo "resolve-review-target: '$TARGET' resolved to 0 reviewable source files." >&2
  echo "This is a fact to report, never a clean bill of health." >&2
  exit 3
fi

if [ "$PRINT_FILES" -eq 1 ]; then
  printf '%s\n' "$FILES"
  exit 0
fi

# ── Measurement ───────────────────────────────────────────────────────────────
count_loc() {
  [ -z "$1" ] && { echo 0; return; }
  printf '%s\n' "$1" | tr '\n' '\0' | xargs -0 cat 2>/dev/null | wc -l | tr -d ' '
}

FILE_COUNT="$(printf '%s\n' "$FILES" | wc -l | tr -d ' ')"
# `loc` is the total across everything resolved under the target — it does not change
# meaning with --include-tests, so a reader can always see what the module really is.
# `source_loc` is the number the size class comes from.
LOC="$(count_loc "$ALL_FILES")"
TEST_COUNT="$(printf '%s\n' "$TEST_FILES" | grep -c . || true)"
if [ "$ALL_TESTS" -eq 1 ] || [ "$INCLUDE_TESTS" -eq 1 ]; then
  SOURCE_LOC="$LOC"
else
  SOURCE_LOC="$(count_loc "$SRC_FILES")"
fi

langs() {
  printf '%s\n' "$FILES" | sed -E 's/.*\.([A-Za-z0-9]+)$/\1/' | LC_ALL=C sort | uniq -c \
    | LC_ALL=C sort -rn | head -5 | awk '{printf "%s:%s,", $2, $1}' | sed 's/,$//'
}

# Surface probes. These COUNT evidence; they never assert absence. A zero means the
# probe found nothing, which the skill body must report as "no signal", not as "safe".
surface_hits() {
  printf '%s\n' "$FILES" | tr '\n' '\0' \
    | xargs -0 grep -lEi "$1" 2>/dev/null | wc -l | tr -d ' '
}

SEC_RE='password|passwd|secret|api[_-]?key|token|auth|jwt|session|subprocess|os\.system|\beval\(|\bexec\(|pickle|deserial|innerHTML|dangerouslySetInnerHTML|cursor\.execute|raw\(|\bsql\b|shell=True|request\.(GET|POST|body|args)'
PERF_RE='\.objects\.|\.filter\(|\.all\(\)|select_related|prefetch_related|SELECT |JOIN |useEffect|useMemo|useCallback|forEach|\.map\(|while |for \(|range\('

SEC_HITS="$(surface_hits "$SEC_RE")"
PERF_HITS="$(surface_hits "$PERF_RE")"

# ── Size class: the cost bound ────────────────────────────────────────────────
# The bound is LOC, not file count: a finder's cost tracks how much it must read.
# `oversize` is a refusal, not a warning — a whole-app run that spawns the same two
# finders over 40k LOC is a sample presented as coverage.
# The bound is SOURCE_LOC — what the finders will actually read — not the total.
if   [ "$SOURCE_LOC" -le 800 ];   then SIZE_CLASS="small";    FINDERS=2
elif [ "$SOURCE_LOC" -le 3000 ];  then SIZE_CLASS="medium";   FINDERS=3
elif [ "$SOURCE_LOC" -le 12000 ]; then SIZE_CLASS="large";    FINDERS=4
else                                   SIZE_CLASS="oversize"; FINDERS=0
fi

# The FINDER FLOOR — not an estimate of what the run costs. ~22k tokens per agent
# (measured in the plan-exec-as-workflow work, recorded in review-scope-conventions.md
# §4). Verifiers are excluded because their count is unknowable before the find phase,
# NOT because they are small: in the one module review measured (2026-08-10,
# register-item.sh, 790 LOC, 6 finders) the run spent ~17x this number. The key is named
# for what it is so no caller can read it as a total.
FINDER_FLOOR_PER_LENS=$(( FINDERS * 22 ))

cat <<EOF
target=$TARGET
whole_app=$WHOLE_APP
files=$FILE_COUNT
loc=$LOC
source_loc=$SOURCE_LOC
test_files=$TEST_COUNT
include_tests=$INCLUDE_TESTS
langs=$(langs)
security_surface_files=$SEC_HITS
perf_surface_files=$PERF_HITS
size_class=$SIZE_CLASS
finders_per_lens=$FINDERS
finder_floor_ktokens_per_lens=$FINDER_FLOOR_PER_LENS
EOF

[ "$SIZE_CLASS" = "oversize" ] && cat >&2 <<EOF
resolve-review-target: $SOURCE_LOC LOC of source is oversize for a single review run.
Split it into modules and review them separately. Running the same finder count over
a target this size produces a sample, and reporting a sample as a review is the
"checkers lie by omission" failure this resolver exists to prevent.
EOF

exit 0
