#!/usr/bin/env bash
# plan-waves.py decides which phases of a multi-file plan launch together.
#
# Layer: the script's CLI over fixture plan directories; the decision is its output line
# and nothing below the CLI can observe it.
#
# Run with: bash skills/plan-exec/tests/test-plan-waves.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
SCRIPT="$ROOT/skills/plan-exec/scripts/plan-waves.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

# phase <dir> <n> <depends_on list> <phase-type> <files line or ''> <done 0|1>
phase() {
  local d="$1" n="$2" box=" "; [ "$6" = 1 ] && box="x"
  mkdir -p "$d"
  { printf -- '---\ndepends_on: [%s]\nphase-type: %s\n---\n\n# Phase %s\n\n' "$3" "$4" "$n"
    [ -n "$5" ] && printf '**Files:** %s\n\n' "$5"
    printf '## Phase %s Checkpoint\n\n**Completed:**\n- [%s] Task\n' "$n" "$box"; } > "$d/0$n-p.md"
}

# check <name> <dir> <expected output>
check() {
  local got; got="$(python3 "$SCRIPT" "$2")"
  if [ "$got" = "$3" ]; then echo "ok: $1"; else printf 'FAIL: %s\n  want: %s\n  got:  %s\n' "$1" "${3//$'\n'/ | }" "${got//$'\n'/ | }"; failures=$((failures+1)); fi
}

d="$TMP/chain"
phase "$d" 1 "" afk-impl '`a.txt`' 0; phase "$d" 2 "1" afk-impl '`b.txt`' 0; phase "$d" 3 "2" afk-impl '`c.txt`' 0
check "linear chain, one phase per wave" "$d" $'wave 1: 1\nwave 2: 2\nwave 3: 3'

d="$TMP/indep"
phase "$d" 1 "" afk-impl '`a.txt`' 0; phase "$d" 2 "" afk-impl 'Create `b.txt`' 0
check "two independent phases share a wave" "$d" "wave 1: 1, 2"

d="$TMP/shared"
phase "$d" 1 "" afk-impl 'Modify `x/a.txt`' 0; phase "$d" 2 "" afk-impl '`x/a.txt`, `b.txt`' 0
check "shared file splits them" "$d" $'wave 1: 1\nwave 2: 2'

d="$TMP/nofiles"
phase "$d" 1 "" afk-impl '' 0; phase "$d" 2 "" afk-impl '`b.txt`' 0
check "missing Files runs alone" "$d" $'wave 1: 1\nwave 2: 2'

d="$TMP/hitl"
phase "$d" 1 "" hitl-align '`a.txt`' 0; phase "$d" 2 "" afk-impl '`b.txt`' 0
check "hitl runs alone" "$d" $'wave 1: 1\nwave 2: 2'

d="$TMP/cap"
for i in 1 2 3 4; do phase "$d" "$i" "" afk-impl "\`f$i.txt\`" 0; done
check "cap of three" "$d" $'wave 1: 1, 2, 3\nwave 2: 4'

d="$TMP/unmet"
phase "$d" 1 "" afk-impl '`a.txt`' 1; phase "$d" 2 "1" afk-impl '`b.txt`' 0; phase "$d" 3 "9" afk-impl '`c.txt`' 0
check "unmet dependency excluded, done dependency satisfied" "$d" $'wave 1: 2\nblocked (unmet or cyclic dependency): 3'

# raw <dir> <n> <front-matter body> <body text> : a hand-written phase file
raw() { mkdir -p "$1"; printf -- '---\n%s\n---\n\n# Phase %s\n\n%s\n' "$3" "$2" "$4" > "$1/0$2-p.md"; }
CK='## Phase N Checkpoint

**Completed:**
'
UNDONE="$CK- [ ] Task"
DONE="$CK- [x] Task"

# F1: one file spelled two ways (line suffix, repo prefix, ~) is the same file
d="$TMP/spell"
phase "$d" 1 "" afk-impl '`skills/p/S.md`' 0; phase "$d" 2 "" afk-impl '`aidex/skills/p/S.md:10-20`' 0
check "same file, prefix and line suffix, splits" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/tilde"
phase "$d" 1 "" afk-impl "\`$HOME/.claude/r.md\`" 0; phase "$d" 2 "" afk-impl '`~/.claude/r.md`' 0
check "~ expands to the home directory" "$d" $'wave 1: 1\nwave 2: 2'

# F2: a glob clashes with a concrete path it matches
d="$TMP/glob"
phase "$d" 1 "" afk-impl '`aidex/skills/*/agents/*.md`' 0; phase "$d" 2 "" afk-impl '`aidex/skills/plan/agents/a.md`' 0
check "glob clashes with a path it matches" "$d" $'wave 1: 1\nwave 2: 2'

# F3: a non-integer depends_on entry blocks the phase
d="$TMP/slug"
raw "$d" 1 $'depends_on: [setup]\nphase-type: afk-impl' $'**Files:** `a.txt`\n\n'"$UNDONE"
check "slug dependency blocks" "$d" "blocked (unmet or cyclic dependency): 1"
d="$TMP/blocklist"
raw "$d" 1 $'depends_on:\n  - setup\nphase-type: afk-impl' $'**Files:** `a.txt`\n\n'"$UNDONE"
check "YAML block-list slug dependency blocks" "$d" "blocked (unmet or cyclic dependency): 1"

# F4: mutants
d="$TMP/partial"   # dependency with one ticked and one unticked box is NOT done
raw "$d" 1 $'depends_on: []\nphase-type: afk-impl' $'**Files:** `a.txt`\n\n'"$CK- [x] A
- [ ] B"
phase "$d" 2 "1" afk-impl '`b.txt`' 0
check "partly ticked dependency is not done" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/aloneafter"
phase "$d" 1 "" afk-impl '`a.txt`' 0; phase "$d" 2 "" afk-impl '' 0; phase "$d" 3 "" afk-impl '`b.txt`' 0
check "alone phase arriving after others waits" "$d" $'wave 1: 1, 3\nwave 2: 2'
d="$TMP/dirprefix"
phase "$d" 1 "" afk-impl '`x/`' 0; phase "$d" 2 "" afk-impl '`x/a.txt`' 0
check "directory clashes with a file under it" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/nobox"      # no checkboxes: never done, so its dependent is blocked
raw "$d" 1 $'depends_on: []\nphase-type: afk-impl' $'**Files:** `a.txt`\n\n## Phase 1 Checkpoint'
phase "$d" 2 "1" afk-impl '`b.txt`' 0
check "phase without checkboxes is never done" "$d" $'wave 1: 1\nwave 2: 2'

# F5: backticked **Files:** inside prose is not a Files line
d="$TMP/prose"
raw "$d" 1 $'depends_on: []\nphase-type: afk-impl' $'Notes say the **Files:** line names `zzz.txt`.\n\n'"$UNDONE"
phase "$d" 2 "" afk-impl '`b.txt`' 0
check "Files marker inside prose is ignored" "$d" $'wave 1: 1\nwave 2: 2'

# F6: a list one blank line after the heading is still the Files list
d="$TMP/listgap"
raw "$d" 1 $'depends_on: []\nphase-type: afk-impl' $'**Files:**\n\n- `a.txt`\n\n'"$UNDONE"
phase "$d" 2 "" afk-impl '`b.txt`' 0
check "Files list after one blank line is read (phase 1 is not alone)" "$d" "wave 1: 1, 2"

# N1: directory and glob clash across spellings (repo prefix dropped on one side)
d="$TMP/dirspell"
phase "$d" 1 "" afk-impl '`aidex/skills/p/`' 0; phase "$d" 2 "" afk-impl '`skills/p/S.md`' 0
check "directory vs file under it, other spelling, splits" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/dirspell2"
phase "$d" 1 "" afk-impl '`aidex/agents`' 0; phase "$d" 2 "" afk-impl '`agents/x.md`' 0
check "bare directory vs file under it, other spelling, splits" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/globspell"
phase "$d" 1 "" afk-impl '`aidex/skills/*/agents/*.md`' 0; phase "$d" 2 "" afk-impl '`skills/aidex/agents/foo.md`' 0
check "glob vs matching file, other spelling, splits" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/globspell2"
phase "$d" 1 "" afk-impl '`aidex/skills/*/S.md`' 0; phase "$d" 2 "" afk-impl '`skills/a/S.md`' 0
check "glob vs file, prefix dropped on the glob side, splits" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/basename"
phase "$d" 1 "" afk-impl '`x/a.txt`' 0; phase "$d" 2 "" afk-impl '`y/a.txt`' 0
check "same basename in different directories stays disjoint" "$d" "wave 1: 1, 2"

# N3: a trailing comment on depends_on does not block
d="$TMP/comment"
phase "$d" 1 "" afk-impl '`a.txt`' 1
raw "$d" 2 $'depends_on: [1]  # needs 1\nphase-type: afk-impl' $'**Files:** `b.txt`\n\n'"$UNDONE"
check "trailing comment on depends_on is ignored" "$d" "wave 1: 2"

[ "$failures" -eq 0 ] && echo "PASS: plan-waves" || echo "FAILED: $failures"
exit "$failures"
