#!/usr/bin/env bash
# `--help` of every script that prints its own header comment must print it WITHOUT the
# leading "# ". The old sites ran `sed 's/^# \?//'`, and `\?` is a GNU extension: macOS
# /usr/bin/sed (BSD) leaves "# " on every line. Three of them (reindex-audits,
# reindex-plans, backfill-indexes) and test-db-preflight also called the helper before
# sourcing it, so a shared helper would exit 127 there.
#
# The "# " cell can only go red where /usr/bin/sed is BSD (macOS); on GNU sed the old
# expression passed too. The two cells below hold on any platform: the block must START
# at the script's own title line (a helper that prints one line or the wrong range fails)
# and must not leak code lines (the old `2,/^$/p` range leaked `set -euo pipefail`,
# `. .../_lib.sh` and `SCRIPT_DIR=` at define-item, sweep-kickoff and sweep-report).
#
# Layer: script contract (process exit code + stdout), run under /usr/bin/sed.
# Run with: bash tests/test-usage-from-header.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
S="$REPO_ROOT/skills"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# <script relative to skills/> [args before --help]
SITES=(
  "audit/scripts/close-audit.sh"
  "audit/scripts/reindex-audits.sh"
  "backlog/scripts/close-item.sh"
  "backlog/scripts/defer-item.sh"
  "backlog/scripts/defer-item.sh defer"
  "backlog/scripts/define-item.sh"
  "backlog/scripts/harvest-commit.sh"
  "backlog/scripts/migrate-priorities.sh"
  "backlog/scripts/register-item.sh"
  "backlog/scripts/start-item.sh"
  "backlog/scripts/sweep-gate.sh"
  "backlog/scripts/sweep-kickoff.sh"
  "backlog/scripts/sweep-report.sh"
  "conventions/scripts/backfill-indexes.sh"
  "plan/scripts/close-plan.sh"
  "plan/scripts/reindex-plans.sh"
  "worktree/scripts/test-db-preflight.sh"
)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

# /usr/bin first: the BSD sed is the one a macOS user gets.
for site in "${SITES[@]}"; do
  set -- $site
  rel="$1"; script="$S/$1"; shift
  out="$(PATH="/usr/bin:/bin:$PATH" bash "$script" "$@" --help 2>"$WORK/err")"; rc=$?
  [[ $rc -eq 0 ]] || { fail "$site --help exited $rc ($(head -c 120 "$WORK/err"))"; continue; }
  [[ -n "$out" ]] || { fail "$site --help printed nothing"; continue; }
  if printf '%s\n' "$out" | grep -q '^# '; then
    fail "$site --help keeps a leading '# ': $(printf '%s\n' "$out" | grep -m1 '^# ')"
  fi
  # First non-empty header line, read independently of the helper. Line 2 is the title
  # (script name first); register-item.sh and migrate-priorities.sh start at line 3.
  start=2; case "$rel" in backlog/scripts/register-item.sh|backlog/scripts/migrate-priorities.sh) start=3 ;; esac
  want="$(awk -v s="$start" 'NR>=s && /^#/ { sub(/^# ?/, ""); if ($0 != "") { print; exit } }' "$script")"
  # The whole block, read independently of the helper: a helper that prints one line,
  # or a wrong range, differs here.
  all="$(awk -v s="$start" 'NR>=s { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$script")"
  [[ "$out" == "$all" ]] || fail "$site --help is not the whole header block"
  first="$(printf '%s\n' "$out" | grep -m1 .)"
  [[ "$first" == "$want" ]] || fail "$site --help starts with '$first', want '$want'"
  [[ $start -ne 2 || "$first" == "$(basename "$script")"* ]] || fail "$site --help does not open with the script name"
  if printf '%s\n' "$out" | grep -Eq '^(set |\. "|[A-Z_]+=)'; then
    fail "$site --help leaks a code line: $(printf '%s\n' "$out" | grep -Em1 '^(set |\. "|[A-Z_]+=)')"
  fi
done

if [[ $failures -eq 0 ]]; then echo "OK: ${#SITES[@]} --help sites strip the comment prefix"; exit 0; fi
printf '%d failure(s)\n' "$failures"; exit 1
