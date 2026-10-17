#!/usr/bin/env bash
# The default `autonomySurface` string is copied (on purpose, owner decision Q32) into
# every workflow asset that builds a ctx: two in plan-exec, one in audit. The arbiter reads
# it as the run's binding rule, so a term added to one copy changes what that form's arbiter
# may decide alone. This pins the copies equal and the set of copying files closed.
#
# Layer: static check over the shipped assets — the string is a literal in each file and
# nothing runs it at test time.
set -uo pipefail

SKILLS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# Overridable so the mutant check can point at a temp tree; production runs use the repo.
ROOT="${WF_SKILLS_ROOT:-$SKILLS}"
EXPECTED='plan-exec/assets/workflows/fan-out-with-gate.workflow.js
plan-exec/assets/workflows/pipeline-with-gate.workflow.js
audit/assets/workflows/audit-fanout.workflow.js'

fail=0
err() { printf 'FAIL: %s\n' "$*"; fail=1; }

# Every workflow asset whose ctx takes a default: found by name, not from the expected list.
found="$(cd "$ROOT" && grep -l 'autonomySurface: cfg.autonomySurface ||' */assets/workflows/*.workflow.js | sort)"
want="$(printf '%s\n' "$EXPECTED" | sort)"
[ "$found" = "$want" ] || err "the files carrying the default changed — expected:
$want
got:
$found
(a new copy must join this list and match; a removed one must leave it)"

ref=""; ref_file=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  line="$(grep -F 'autonomySurface: cfg.autonomySurface ||' "$ROOT/$f" | sed -n 1p)"
  def="$(printf '%s' "$line" | sed -n "s/.*cfg\.autonomySurface || '\(.*\)',[[:space:]]*\$/\1/p")"
  [ -n "$def" ] || { err "$f: cannot read the default string from: $line"; continue; }
  if [ -z "$ref" ]; then ref="$def"; ref_file="$f"
  elif [ "$def" != "$ref" ]; then err "$f default differs from $ref_file:
  $ref_file: $ref
  $f: $def"; fi
done <<<"$found"

[ "$fail" -eq 0 ] && echo "OK — the default autonomySurface is identical in all 3 workflow assets"
exit "$fail"
