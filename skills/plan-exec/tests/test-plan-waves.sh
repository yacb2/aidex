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

# plan-exec-c04: an unbracketed comma scalar is a list, not one slug
d="$TMP/commascalar"
phase "$d" 1 "" afk-impl '`a.txt`' 1; phase "$d" 2 "" afk-impl '`b.txt`' 0
raw "$d" 3 $'depends_on: 1, 2\nphase-type: afk-impl' $'**Files:** `c.txt`\n\n'"$UNDONE"
check "unbracketed comma depends_on is a list" "$d" $'wave 1: 2\nwave 2: 3'

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

# N4: a glob clashes with every path it can match, or that holds or sits under a match,
# under any spelling (either side may lack leading components); a glob on another tree
# stays disjoint
d="$TMP/globtail"
phase "$d" 1 "" afk-impl '`frontend/src/App.vue`' 0; phase "$d" 2 "" afk-impl '`frontend-next/src/app.tsx`, `frontend-next/messages/*`' 0
check "glob on a disjoint tree stays disjoint" "$d" "wave 1: 1, 2"
d="$TMP/globtail2"
phase "$d" 1 "" afk-impl '`frontend-next/messages/*`' 0; phase "$d" 2 "" afk-impl '`messages/en.json`' 0
check "glob vs file under its literal prefix, other spelling, splits" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/globtail3"  # y/S.md is x/y/S.md with x/ dropped
phase "$d" 1 "" afk-impl '`x/*/S.md`' 0; phase "$d" 2 "" afk-impl '`y/S.md`' 0
check "glob vs file it matches with the literal prefix dropped, splits" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/globtail4"
phase "$d" 1 "" afk-impl '`x/*/S.md`' 0; phase "$d" 2 "" afk-impl '`z/T.md`' 0
check "glob vs file it cannot match stays disjoint" "$d" "wave 1: 1, 2"
d="$TMP/globtail5"  # skills/... is aidex/skills/... with aidex/ dropped
phase "$d" 1 "" afk-impl '`aidex/**`' 0; phase "$d" 2 "" afk-impl '`skills/plan-exec/SKILL.md`' 0
check "recursive glob vs file under it, other spelling, splits" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/globtail6"
phase "$d" 1 "" afk-impl '`x/*`' 0; phase "$d" 2 "" afk-impl '`a.txt`' 0
check "trailing-star glob vs file it matches, other spelling, splits" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/globtail7"
phase "$d" 1 "" afk-impl '`x/*/*`' 0; phase "$d" 2 "" afk-impl '`y/S.md`' 0
check "all-star tail vs file it matches, other spelling, splits" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/globtail8"  # [id] is a literal route segment, not a character class
phase "$d" 1 "" afk-impl '`app/*/[id]/page.tsx`' 0; phase "$d" 2 "" afk-impl '`users/[id]/page.tsx`' 0
check "brackets are literal in a glob, other spelling, splits" "$d" $'wave 1: 1\nwave 2: 2'

# N3: a trailing comment on depends_on does not block
d="$TMP/comment"
phase "$d" 1 "" afk-impl '`a.txt`' 1
raw "$d" 2 $'depends_on: [1]  # needs 1\nphase-type: afk-impl' $'**Files:** `b.txt`\n\n'"$UNDONE"
check "trailing comment on depends_on is ignored" "$d" "wave 1: 2"

# refuse <name> <stderr substring> [args...] : non-zero exit, the message on stderr, no stdout
refuse() {
  local name="$1" want="$2" got rc; shift 2
  got="$(python3 "$SCRIPT" "$@" 2>"$TMP/err")"; rc=$?
  if [ "$rc" -ne 0 ] && [ -z "$got" ] && grep -qF -- "$want" "$TMP/err"; then echo "ok: $name"
  else printf 'FAIL: %s\n  want: rc!=0, no stdout, stderr has: %s\n  got:  rc=%s stdout=%s stderr=%s\n' "$name" "$want" "$rc" "${got//$'\n'/ | }" "$(tr '\n' ' ' < "$TMP/err")"; failures=$((failures+1)); fi
}

# c01: a block list stops at the next key; null / none mean no dependencies
d="$TMP/depkeys"
phase "$d" 1 "" afk-impl '`a.txt`' 1
raw "$d" 2 $'depends_on:\n  - 1\ntags:\n  - backend\nphase-type: afk-impl' $'**Files:** `b.txt`\n\n'"$UNDONE"
raw "$d" 3 $'depends_on: null\nphase-type: afk-impl' $'**Files:** `c.txt`\n\n'"$UNDONE"
raw "$d" 4 $'depends_on: none\nphase-type: afk-impl' $'**Files:** `d.txt`\n\n'"$UNDONE"
check "block list ends at the next key, null and none are no dependency" "$d" "wave 1: 2, 3, 4"
d="$TMP/depcomment"  # a YAML comment line inside the block list does not end it
phase "$d" 1 "" afk-impl '`a.txt`' 0
raw "$d" 2 $'depends_on:\n  # needs the schema\n  - 1\nphase-type: afk-impl' $'**Files:** `b.txt`\n\n'"$UNDONE"
check "comment line inside a block-list depends_on is skipped" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/deptilde"
raw "$d" 1 $'depends_on: ~\nphase-type: afk-impl' $'**Files:** `a.txt`\n\n'"$UNDONE"
check "depends_on: ~ is no dependency" "$d" "wave 1: 1"

# c02: done is read from the Checkpoint section only; a file without one (pre-template)
# falls back to every box in the file
d="$TMP/cksection"
raw "$d" 1 $'depends_on: []\nphase-type: afk-impl' $'**Files:** `a.txt`\n\nSee the Checkpoint below.\n\n## Notes\n\n- [ ] optional follow-up\n\n'"$DONE"$'\n\n## Follow-ups\n\n- [ ] later'
phase "$d" 2 "1" afk-impl '`b.txt`' 0
check "only the Checkpoint section's boxes decide done" "$d" "wave 1: 2"
# every Checkpoint heading opens a section up to the next heading of its level or higher;
# done iff the union of their boxes is non-empty and all ticked
ckrows() {  # ckrows <name> <phase 1 body> <expected>
  local d="$TMP/ck-$1"
  raw "$d" 1 $'depends_on: []\nphase-type: afk-impl' $'**Files:** `a.txt`\n\n'"$2"
  phase "$d" 2 "1" afk-impl '`b.txt`' 0
  check "Checkpoint sections: $1" "$d" "$3"
}
ckrows "ab, unticked A is not hidden by a ticked B" $'### Phase Checkpoint (A)\n\n- [ ] A1\n\n### Phase Checkpoint (B)\n\n- [x] B1' $'wave 1: 1\nwave 2: 2'
ckrows "ba, unticked B is not hidden by a ticked A" $'### Phase Checkpoint (A)\n\n- [x] A1\n\n### Phase Checkpoint (B)\n\n- [ ] B1' $'wave 1: 1\nwave 2: 2'
ckrows "nest, a box-less Checkpoint sub-heading does not undo a ticked section" $'## Phase 1 Checkpoint\n\n- [x] T1\n- [x] T2\n\n### Checkpoint notes\n\nAdjusted X.' "wave 1: 2"
ckrows "fence, a # line in a code block does not end the section" $'## Phase 1 Checkpoint\n\n- [x] Task 1.1\n\n```bash\n# run the gate\nmake test\n```\n\n- [ ] Task 1.2' $'wave 1: 1\nwave 2: 2'
ckrows "sub, a deeper sub-heading does not end the section" $'## Phase 1 Checkpoint\n\n### Completed\n\n- [x] T1' "wave 1: 2"
d="$TMP/nockpt"
raw "$d" 1 $'depends_on: []\nphase-type: afk-impl' $'**Files:** `a.txt`\n\n## Acceptance\n\n- [x] A\n- [x] B'
phase "$d" 2 "1" afk-impl '`b.txt`' 0
check "no Checkpoint section, every box ticked: done" "$d" "wave 1: 2"
d="$TMP/nockptopen"
raw "$d" 1 $'depends_on: []\nphase-type: afk-impl' $'**Files:** `a.txt`\n\n## Acceptance\n\n- [x] A\n- [ ] B'
phase "$d" 2 "1" afk-impl '`b.txt`' 0
check "no Checkpoint section, one box unticked: pending" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/nockptnobox"
raw "$d" 1 $'depends_on: []\nphase-type: afk-impl' $'**Files:** `a.txt`\n\n## Acceptance\n\nAll good.'
phase "$d" 2 "1" afk-impl '`b.txt`' 0
check "no Checkpoint section, no boxes: pending" "$d" $'wave 1: 1\nwave 2: 2'

# c03: bad invocation never looks like "every phase done"
d="$TMP/noplan"; mkdir -p "$d"; printf -- '---\ntitle: x\n---\n' > "$d/00-index.md"
refuse "no argument" "usage:"
refuse "nonexistent plan dir" "not a directory" "$TMP/missing"
refuse "file path instead of plan dir" "not a directory" "$d/00-index.md"
refuse "directory with no phase files" "no phase files" "$d"

# c13: a phase file is NN-<phase>.md; other digit-led names are skipped with one stderr
# line; two phase files with one number are refused, both named
d="$TMP/dupnum"
phase "$d" 1 "" afk-impl '`a.txt`' 0
raw "$d" 2 $'depends_on: [1]\nphase-type: afk-impl' $'**Files:** `b.txt`\n\n'"$UNDONE"; mv "$d/02-p.md" "$d/1-b.md"
refuse "duplicate phase number refused" "duplicate phase number 1: 01-p.md, 1-b.md" "$d"
d="$TMP/briefs"     # the echo_lab access-delivery shape: delegate briefs beside phases
phase "$d" 9 "" afk-impl '`a.txt`' 0; mv "$d/09-p.md" "$d/09-x.md"
phase "$d" 10 "9" afk-impl '`b.txt`' 0; mv "$d/010-p.md" "$d/10-z.md"
printf '# Brief\n\nBuild the backend.\n' > "$d/9.2-y-brief.md"
printf '# Brief\n\nAnswer Q6a.\n' > "$d/10.1-w-brief.md"
printf '# Handoff\n\nNotes.\n' > "$d/2026-05-14-session-handoff.md"
got="$(python3 "$SCRIPT" "$d" 2>"$TMP/err")"; rc=$?
if [ "$rc" -eq 0 ] && [ "$got" = $'wave 1: 9\nwave 2: 10' ] && [ "$(wc -l < "$TMP/err")" -eq 1 ] \
   && grep -qF 9.2-y-brief.md "$TMP/err" && grep -qF 10.1-w-brief.md "$TMP/err" \
   && grep -qF 2026-05-14-session-handoff.md "$TMP/err"; then echo "ok: non-phase files skipped, named once on stderr"
else printf 'FAIL: non-phase files skipped, named once on stderr\n  want: rc=0 wave 1: 9 | wave 2: 10, one stderr line naming both briefs and the dated file\n  got:  rc=%s stdout=%s stderr=%s\n' "$rc" "${got//$'\n'/ | }" "$(tr '\n' ' ' < "$TMP/err")"; failures=$((failures+1)); fi

# BL-861: /aidex:ui-contract writes phase 0 as 00-ui-contract.md; only 00-index.md is not a
# phase (an index parsed as a phase would collide as a second phase 0 and be refused)
uicontract() {  # uicontract <dir> <done 0|1>
  local box=" "; [ "$2" = 1 ] && box="x"
  mkdir -p "$1"
  printf -- '---\ntitle: x\n---\n\n| Phase | Status |\n|---|---|\n| 0 | - [ ] |\n' > "$1/00-index.md"
  printf -- '---\ndepends_on: []\nphase-type: hitl-align\n---\n\n# Phase 0: UI contract\n\n## Phase 0 Checkpoint\n\n- [%s] Owner approved\n' "$box" > "$1/00-ui-contract.md"
  phase "$1" 1 "0" afk-impl '`a.txt`' 0; phase "$1" 2 "0" afk-impl '`b.txt`' 0
}
d="$TMP/ui0done"; uicontract "$d" 1
check "ticked 00-ui-contract.md is phase 0, done: its dependents run" "$d" "wave 1: 1, 2"
d="$TMP/ui0open"; uicontract "$d" 0
check "unticked 00-ui-contract.md is phase 0, pending: it runs first" "$d" $'wave 1: 0\nwave 2: 1, 2'

# c28: backticked symbols inside the template's parentheses are not paths; a path with a
# directory inside parentheses still is (fail closed)
d="$TMP/symbols"
raw "$d" 1 $'depends_on: []\nphase-type: afk-impl' $'**Files:**\n- Modify: `src/b.py` (`Foo.bar` — after the `speed_override` field)\n\n'"$UNDONE"
raw "$d" 2 $'depends_on: []\nphase-type: afk-impl' $'**Files:**\n- Modify: `src/c.py` (`Foo.bar` — after the `speed_override` field)\n\n'"$UNDONE"
raw "$d" 3 $'depends_on: []\nphase-type: afk-impl' $'**Files:**\n- Create: `src/d.py` (split out of `src/b.py`)\n\n'"$UNDONE"
check "symbols in parentheses do not clash, a path in them does" "$d" $'wave 1: 1, 2\nwave 2: 3'
d="$TMP/slashparen"  # a path with a directory in parentheses is a full path on both sides
raw "$d" 1 $'depends_on: []\nphase-type: afk-impl' $'**Files:**\n- Create: `src/x.py` (split out of `src/old.py`)\n\n'"$UNDONE"
raw "$d" 2 $'depends_on: []\nphase-type: afk-impl' $'**Files:**\n- Create: `src/y.py` (split out of `src/old.py`)\n\n'"$UNDONE"
check "slashed path in parentheses on both sides clashes" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/routegroup"  # parentheses inside a backticked path are part of the path
phase "$d" 1 "" afk-impl '`app/(auth)/page.tsx`' 0; phase "$d" 2 "" afk-impl '`app/(auth)/page.tsx`' 0
check "route-group path in backticks is still a path" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/weak"  # a slashless name in parentheses still clashes with a real path
raw "$d" 1 $'depends_on: []\nphase-type: afk-impl' $'**Files:**\n- Create: `src/api/mutations.ts` (or extend `doctorApi.ts`)\n\n'"$UNDONE"
raw "$d" 2 $'depends_on: []\nphase-type: afk-impl' $'**Files:**\n- Modify: `src/api/doctorApi.ts`\n\n'"$UNDONE"
check "name in parentheses clashes with the path it names" "$d" $'wave 1: 1\nwave 2: 2'
d="$TMP/weakrev"  # the same pair with the parenthesised name in the later phase
raw "$d" 1 $'depends_on: []\nphase-type: afk-impl' $'**Files:**\n- Modify: `src/api/doctorApi.ts`\n\n'"$UNDONE"
raw "$d" 2 $'depends_on: []\nphase-type: afk-impl' $'**Files:**\n- Create: `src/api/mutations.ts` (or extend `doctorApi.ts`)\n\n'"$UNDONE"
check "name in parentheses clashes with the path it names, either order" "$d" $'wave 1: 1\nwave 2: 2'

# --fanout (plan-exec Q22a): a fan-out run launches every dependency-ready phase together, so
# the check refuses, before anything is written, a wave whose phases share a file.
# fanout <name> <dir> <expected exit> <stderr must contain...>
fanout() {
  local name="$1" d="$2" want="$3" err rc; shift 3
  err="$(python3 "$SCRIPT" "$d" --fanout 2>&1 >/dev/null)"; rc=$?
  local bad=0; [ "$rc" = "$want" ] || bad=1
  for needle in "$@"; do case "$err" in *"$needle"*) ;; *) bad=1 ;; esac; done
  if [ "$bad" = 0 ]; then echo "ok: $name"; else printf 'FAIL: %s\n  want exit %s containing %s\n  got exit %s: %s\n' "$name" "$want" "$*" "$rc" "$err"; failures=$((failures+1)); fi
}
d="$TMP/fo-shared"
phase "$d" 1 "" afk-impl '`pkg/__init__.py`, `a.txt`' 0; phase "$d" 2 "" afk-impl '`pkg/__init__.py`' 0
fanout "fan-out refuses a wave sharing a file, naming both phases and the file" "$d" 1 "01-p.md" "02-p.md" "pkg/__init__.py"
d="$TMP/fo-disjoint"
phase "$d" 1 "" afk-impl '`a.txt`' 0; phase "$d" 2 "" afk-impl '`b.txt`' 0
fanout "fan-out accepts disjoint phases" "$d" 0
d="$TMP/fo-chain"
phase "$d" 1 "" afk-impl '`a.txt`' 0; phase "$d" 2 "1" afk-impl '`a.txt`' 0
fanout "fan-out accepts a shared file across dependency waves" "$d" 0
d="$TMP/fo-later"
phase "$d" 1 "" afk-impl '`a.txt`' 0; phase "$d" 2 "1" afk-impl '`x.txt`' 0; phase "$d" 3 "1" afk-impl '`x.txt`' 0
fanout "fan-out checks later waves too" "$d" 1 "02-p.md" "03-p.md" "x.txt"
d="$TMP/fo-nofiles"
phase "$d" 1 "" afk-impl '' 0; phase "$d" 2 "" afk-impl '`b.txt`' 0
fanout "fan-out refuses a wave member with no declared files (disjointness unprovable)" "$d" 1 "01-p.md"
d="$TMP/fo-slug"
phase "$d" 1 "" afk-impl '`a.txt`' 0; phase "$d" 2 "setup" afk-impl '`x.txt`' 0; phase "$d" 3 "setup" afk-impl '`x.txt`' 0
fanout "fan-out refuses phases no wave can reach (unresolvable depends_on), naming them" "$d" 1 "02-p.md" "03-p.md"
d="$TMP/fo-hitl"
phase "$d" 1 "" hitl-align '' 0; phase "$d" 2 "" afk-impl '`b.txt`' 0
fanout "fan-out leaves a hitl phase out of the wave" "$d" 0
d="$TMP/fo-lone"
phase "$d" 1 "" afk-impl '' 0
fanout "a lone no-Files phase in its own wave is accepted" "$d" 0

[ "$failures" -eq 0 ] && echo "PASS: plan-waves" || echo "FAILED: $failures"
exit "$failures"
