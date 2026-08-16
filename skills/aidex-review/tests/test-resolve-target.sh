#!/usr/bin/env bash
# test-resolve-target.sh — cells for resolve-review-target.sh.
#
# The cells that matter are the refusals. A resolver that silently defaults to the
# repo root, or prints an empty set as if it were a clean result, is the failure mode
# this script exists to prevent — so "no target" and "empty target" get a cell each,
# and the oversize refusal gets one because a whole-app run is exactly where a sample
# would otherwise be reported as coverage.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RESOLVER="$SCRIPT_DIR/../scripts/resolve-review-target.sh"
FAILURES=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }

run() { bash "$RESOLVER" "$@" 2>/dev/null; }
run_code() { bash "$RESOLVER" "$@" >/dev/null 2>&1; echo $?; }
field() { local key="$1"; shift; run "$@" | grep "^$key=" | cut -d= -f2-; }

# ── Fixture: a small module with one source file and one test ─────────────────
mkdir -p "$TMP/mod/tests" "$TMP/mod/node_modules/pkg"
printf 'def f():\n    return 1\n' > "$TMP/mod/app.py"
printf 'def test_f():\n    assert True\n' > "$TMP/mod/tests/test_app.py"
printf 'var junk = 1;\n' > "$TMP/mod/node_modules/pkg/index.js"
printf 'notes\n' > "$TMP/mod/README.md"

echo "resolve-review-target cells:"

# 1. No target at all must be refused, never defaulted. This is the cell that
#    encodes "the projects root has no default and refuses to run without one".
[ "$(run_code)" = "2" ] || fail "no target: expected exit 2, got $(run_code)"

# 2. A nonexistent path is a usage error, not an empty review.
[ "$(run_code "$TMP/nope")" = "2" ] || fail "missing path: expected exit 2"

# 3. A path with no source files exits 3 — distinguishable from 'nothing found'.
mkdir -p "$TMP/docs"; printf 'text\n' > "$TMP/docs/a.md"
[ "$(run_code "$TMP/docs")" = "3" ] || fail "empty target: expected exit 3, got $(run_code "$TMP/docs")"

# 4. Two targets is a usage error (a silent second target would widen the review).
[ "$(run_code "$TMP/mod" "$TMP/docs")" = "2" ] || fail "two targets: expected exit 2"

# 5. --app takes no path.
[ "$(run_code --app "$TMP/mod")" = "2" ] || fail "--app with path: expected exit 2"

# 6. Generated and vendored trees are excluded; non-source files are not counted.
#    `files` is the REVIEWED set, which excludes tests by default (cell 12) — the test
#    is still resolved and still counted, in test_files.
files="$(field files "$TMP/mod")"
[ "$files" = "1" ] || fail "file count: expected 1 reviewed (app.py; the test is counted in test_files), got '$files'"
[ "$(field files --include-tests "$TMP/mod")" = "2" ] || fail "--include-tests should bring the count back to 2"
if run --files "$TMP/mod" | grep -q node_modules; then
  fail "node_modules leaked into the resolved file set"
fi
if run --files "$TMP/mod" | grep -q 'README.md'; then
  fail "a non-source file leaked into the resolved file set"
fi

# 7. Test files are counted separately — a module with no tests reviews differently
#    from one with tests, and the triage needs to see that.
[ "$(field test_files "$TMP/mod")" = "1" ] || fail "test_files: expected 1"

# 8. Size class bounds the finder count, and small targets get the cheap tier.
[ "$(field size_class "$TMP/mod")" = "small" ] || fail "size_class: expected small"
[ "$(field finders_per_lens "$TMP/mod")" = "2" ] || fail "finders_per_lens: expected 2 for small"

# 9. Oversize is a refusal with a zero finder count, so no caller can read it as a
#    normal run. Built as one big file so the cell does not depend on the repo.
mkdir -p "$TMP/big"
awk 'BEGIN { for (i = 0; i < 13000; i++) print "x = " i }' > "$TMP/big/huge.py"
[ "$(field size_class "$TMP/big")" = "oversize" ] || fail "size_class: expected oversize for 13k LOC"
[ "$(field finders_per_lens "$TMP/big")" = "0" ] || fail "oversize must yield 0 finders, not a default tier"
if ! bash "$RESOLVER" "$TMP/big" 2>&1 >/dev/null | grep -q "oversize"; then
  fail "oversize target printed no refusal on stderr"
fi

# 10. Surface probes count evidence and are never negative-asserting: a file that
#     mentions a secret is counted, and a file that does not is simply not counted.
printf 'API_KEY = "x"\ncursor.execute(q)\n' > "$TMP/mod/creds.py"
[ "$(field security_surface_files "$TMP/mod")" -ge 1 ] || fail "security surface probe found nothing in a file with API_KEY"

# 11. The cost key is a FLOOR and is named as one, and SKILL.md quotes the name the
#     script actually prints. Registry-lag drift — a heredoc key with one prose
#     consumer — is this repo's named failure mode, so the two are asserted together.
[ "$(field finder_floor_ktokens_per_lens "$TMP/mod")" = "44" ] \
  || fail "finder_floor_ktokens_per_lens: expected 44 (2 finders x 22k) for small"
if run "$TMP/mod" | grep -q 'est_ktokens_per_lens'; then
  fail "the old est_ktokens_per_lens key is still emitted — it reads as a total, which it is not"
fi
SKILL_MD="$(dirname "$RESOLVER")/../SKILL.md"
if ! grep -q 'finder_floor_ktokens_per_lens' "$SKILL_MD"; then
  fail "SKILL.md does not name the cost key the resolver prints"
fi

# 12. The size class bounds what the FINDERS READ, so it is computed on the source
#     files, not on source+tests. A module is otherwise refused for being well tested:
#     echo_lab's lab_timeline measured 15,394 LOC (oversize, 0 finders) against 7,270
#     LOC of source (large, 4 finders) — 8,124 of those lines were its own tests.
#     `loc` keeps meaning the total; `source_loc` is the number the class comes from.
mkdir -p "$TMP/tested/tests"
awk 'BEGIN { for (i = 0; i < 1200; i++) print "x = " i }' > "$TMP/tested/app.py"
awk 'BEGIN { for (i = 0; i < 4000; i++) print "assert " i }' > "$TMP/tested/tests/test_app.py"
[ "$(field loc "$TMP/tested")" = "5200" ] || fail "loc must stay the total, got $(field loc "$TMP/tested")"
[ "$(field source_loc "$TMP/tested")" = "1200" ] || fail "source_loc: expected 1200, got $(field source_loc "$TMP/tested")"
[ "$(field size_class "$TMP/tested")" = "medium" ] \
  || fail "class must come from source_loc (1200 = medium), got $(field size_class "$TMP/tested") — a well-tested module was penalised by its tests"
[ "$(field loc "$TMP/tested")" != "$(field source_loc "$TMP/tested")" ] \
  || fail "loc and source_loc collapsed to one number — the distinction is the fix"

# 13. ...and the class must bound what is read, so --include-tests puts the tests back
#     in the reviewed set AND sizes on the total. Sizing on source while the finders
#     read tests would be a cost bound that does not bound the cost.
[ "$(field files "$TMP/tested")" = "1" ] || fail "default reviewed set must exclude tests, got $(field files "$TMP/tested") files"
[ "$(field files --include-tests "$TMP/tested")" = "2" ] || fail "--include-tests must add the test files back"
[ "$(field size_class --include-tests "$TMP/tested")" = "large" ] \
  || fail "--include-tests must size on the total (5200 = large), got $(field size_class --include-tests "$TMP/tested")"

# 14. A target that is ENTIRELY tests was named deliberately — excluding them would
#     resolve it to zero files and report exit 3, which reads as "nothing to review"
#     on a directory full of code. Measured against echo_lab: lab_timeline/tests is
#     46 files, all of them tests.
mkdir -p "$TMP/onlytests"
printf 'def test_a():\n    assert True\n' > "$TMP/onlytests/test_a.py"
printf 'def test_b():\n    assert True\n' > "$TMP/onlytests/test_b.py"
[ "$(run_code "$TMP/onlytests")" = "0" ] || fail "an all-tests target must resolve, not exit 3"
[ "$(field files "$TMP/onlytests")" = "2" ] || fail "an all-tests target must keep its files"

# 15. Test detection: the named conventions the first pass missed, and no false
#     positives. Measured against four real repos — the misses were __tests__/ helpers
#     with no .test/.spec suffix and conftest.py (2 of 118 test files; the rest of the
#     apparent misses were under .venv, already excluded as vendored).
mkdir -p "$TMP/conv/__tests__" "$TMP/conv/src"
printf 'x = 1\n' > "$TMP/conv/__tests__/helper.ts"
printf 'x = 1\n' > "$TMP/conv/conftest.py"
printf 'x = 1\n' > "$TMP/conv/src/latest.ts"
printf 'x = 1\n' > "$TMP/conv/src/protest_utils.py"
[ "$(field test_files "$TMP/conv")" = "2" ] \
  || fail "expected __tests__/helper.ts + conftest.py counted as tests, got $(field test_files "$TMP/conv")"
[ "$(field source_loc "$TMP/conv")" = "2" ] \
  || fail "latest.ts and protest_utils.py must NOT be read as tests (false positives), source_loc=$(field source_loc "$TMP/conv")"

# 16. --finders decouples depth from size. The size class was meant as a ceiling on
#     cost and had silently become the floor on depth: to get 4 finders you had to
#     point at something big, which is the opposite of what "review this small file
#     thoroughly" wants. /code-review scales its angles by EFFORT and treats diff size
#     as a precondition; we had the two swapped.
[ "$(field finders_per_lens --finders 4 "$TMP/mod")" = "4" ] \
  || fail "--finders 4 on a small target: expected 4, got $(field finders_per_lens --finders 4 "$TMP/mod")"
[ "$(field finder_floor_ktokens_per_lens --finders 4 "$TMP/mod")" = "88" ] \
  || fail "the cost floor must follow the override (4 x 22k), got $(field finder_floor_ktokens_per_lens --finders 4 "$TMP/mod")"
[ "$(field size_class --finders 4 "$TMP/mod")" = "small" ] \
  || fail "--finders must not rewrite the measured size class"

# 17. It is capped at the angle catalog's own maximum. Asking for 8 finders cannot
#     produce 8 angles — correctness has 4 in the catalog and security has 2 — so an
#     uncapped override would announce coverage the catalog cannot supply.
[ "$(field finders_per_lens --finders 9 "$TMP/mod")" = "4" ] \
  || fail "--finders must clamp to the catalog max of 4, got $(field finders_per_lens --finders 9 "$TMP/mod")"
[ "$(run_code --finders 0 "$TMP/mod")" = "2" ] || fail "--finders 0 must be a usage error"
[ "$(run_code --finders abc "$TMP/mod")" = "2" ] || fail "--finders abc must be a usage error"

# 18. It must NOT override the oversize refusal. Depth and admissibility are different
#     questions: if --finders could buy its way past oversize, the refusal that stops a
#     sample being reported as coverage would be one flag away from useless.
[ "$(field finders_per_lens --finders 4 "$TMP/big")" = "0" ] \
  || fail "--finders bought its way past the oversize refusal"
[ "$(field size_class --finders 4 "$TMP/big")" = "oversize" ] || fail "oversize must survive --finders"

# ── Partition: oversize proposes a split instead of stopping at a wall ────────
# The refusal was correct and useless: it said "split it into modules" and named none,
# leaving the whole job to the reader. `--partition` emits the split it is refusing in
# favour of. The refusal itself is unchanged — this is a plan, not a bypass.
mkdir -p "$TMP/part/alpha" "$TMP/part/beta" "$TMP/part/tests"
awk 'BEGIN { for (i = 0; i < 13000; i++) print "x = " i }' > "$TMP/part/alpha/a.py"  # still oversize
awk 'BEGIN { for (i = 0; i < 6500; i++) print "x = " i }' > "$TMP/part/beta/b.py"    # large, splits fine
printf 'x = 1\n' > "$TMP/part/urls.py"          # root-level file
printf 'x = 1\n' > "$TMP/part/tasks.py"         # root-level file
printf 'def test_x():\n    pass\n' > "$TMP/part/tests/test_x.py"

# 19. THE INVARIANT. A partition that loses files is a completeness claim that is
#     false, which is the exact failure this skill exists to stop. Found by attacking
#     the design: echo_lab's lab_timeline has tasks.py and urls.py sitting at the
#     module root, and a naive by-subdirectory split drops them silently.
#
#     The relation is `parts >= whole`, not `=`: a part measured as a target in its
#     own right can carry files the parent excluded (cell 24). Here no part does, so
#     equality is the right assertion for THIS fixture and the wider one is cell 26.
part_out="$(run --partition "$TMP/part")"
sum_parts="$(printf '%s\n' "$part_out" | sed -n 's/^part\.[^.]*\.files=\([0-9]*\)$/\1/p' | awk '{s+=$1} END {print s+0}')"
whole="$(field files "$TMP/part")"
[ "$sum_parts" = "$whole" ] \
  || fail "partition invariant broken: parts sum to $sum_parts, whole is $whole — files were dropped"

# 19b. A subdirectory that is ENTIRELY tests must not become a part. Measured on its
#      own it resolves (the all-tests fallback exists so "review the tests" works), but
#      the partition is a plan for reviewing the PARENT, whose policy excluded them.
#      Without this the split silently widens the review to what the caller opted out of.
printf '%s\n' "$part_out" | grep -q '^part\.tests\.' \
  && fail "an all-tests subdirectory became a part of a partition that excludes tests"

# 20. ...and the root part must be NAMED, not merely counted. A reader who cannot see
#     it will not review it, and "the sum happens to add up" is not a report.
printf '%s\n' "$part_out" | grep -q '^part\.(root)\.files=2$' \
  || fail "the 2 root-level files are not reported as their own named part"

# 21. Every part carries its own measurement, and a part that is STILL oversize is
#     marked as needing another level. `pages/` in echo_lab's timeline is 12,712 LOC
#     of source — over the bound by 6% — so a depth-1 partition does not always
#     converge, and a proposal whose failure mode is the same wall one level down
#     would be no better than the wall.
printf '%s\n' "$part_out" | grep -q '^part\.alpha\.size_class=oversize$' \
  || fail "an oversize part must be reported as oversize"
printf '%s\n' "$part_out" | grep -q '^part\.alpha\.needs_split=yes$' \
  || fail "an oversize part must be flagged as needing another level"
printf '%s\n' "$part_out" | grep -q '^partitionable=yes$' || fail "expected partitionable=yes"

# 22. A flat target has no subdirectories to split on. That is a terminal state and
#     must say so — silently returning one part equal to the whole is a proposal that
#     proposes nothing.
mkdir -p "$TMP/flat"
awk 'BEGIN { for (i = 0; i < 13000; i++) print "x = " i }' > "$TMP/flat/one.py"
flat_out="$(run --partition "$TMP/flat")"
printf '%s\n' "$flat_out" | grep -q '^partitionable=no$' \
  || fail "a flat oversize target must report partitionable=no, not a one-part split"
printf '%s\n' "$flat_out" | grep -q '^partition_note=' \
  || fail "partitionable=no must come with a note saying what to do instead"

# 23. --partition does not lift the refusal it explains.
[ "$(field finders_per_lens --partition "$TMP/part")" = "0" ] \
  || fail "--partition must not turn an oversize target into a runnable one"

# ── Parts are measured as targets in their own right (BL-161) ────────────────
# They were not: skill detection was decided once from the top-level target and the
# partition bucketed the already-filtered file set, so a part that is itself a skill
# was measured under its parent's rules -- without its markdown. Measured on this repo
# 2026-08-11: `--partition skills` reported aidex-audit at 3,428 LOC where the same
# path as a target reads 4,748, and SEVEN markdown-only skills (aidex-bugfix,
# aidex-decision, aidex-loop, aidex-request, aidex-research, aidex-skill,
# aidex-workflow -- 14 files, 1,503 LOC) did not appear at all. A caller following the
# plan reviewed less than the plan claimed, and never saw those seven: the same lie by
# omission this resolver exists to prevent, inside the instrument meant to prevent it.
mkdir -p "$TMP/pskill/alpha" "$TMP/pskill/skillish" "$TMP/pskill/mdonly"
awk 'BEGIN { for (i = 0; i < 13000; i++) print "x = " i }' > "$TMP/pskill/alpha/a.py"
awk 'BEGIN { for (i = 0; i < 400; i++) print "# doc " i }' > "$TMP/pskill/skillish/SKILL.md"
printf 'echo hi\n' > "$TMP/pskill/skillish/run.sh"
awk 'BEGIN { for (i = 0; i < 300; i++) print "# doc " i }' > "$TMP/pskill/mdonly/SKILL.md"
printf 'x = 1\n' > "$TMP/pskill/root.py"
ps_out="$(run --partition "$TMP/pskill")"

# 24. A part carrying a SKILL.md is measured as a skill: its markdown is source,
#     because for a skill the markdown IS the code (that is what ca91e5d established
#     for the top-level target, and a part is a target).
printf '%s\n' "$ps_out" | grep -q '^part\.skillish\.files=2$' \
  || fail "a skill part must count its SKILL.md: expected 2 files, got $(printf '%s\n' "$ps_out" | grep '^part\.skillish\.files=' || echo none)"

# 25. ...and a part whose ONLY source is markdown must appear at all. This is the
#     half that erases whole modules rather than shrinking them.
printf '%s\n' "$ps_out" | grep -q '^part\.mdonly\.files=1$' \
  || fail "a markdown-only skill part vanished from the partition"
printf '%s\n' "$ps_out" | grep -q '^part\.mdonly\.source_loc=300$' \
  || fail "a markdown-only part must carry its real LOC"

# 26. THE INVARIANT, in its honest form. Once parts can carry files the parent
#     excluded, `parts = whole` is false and `parts >= whole` is the relation. Assert
#     the strict case too, so this cannot be satisfied by reverting to bucketing.
ps_sum="$(printf '%s\n' "$ps_out" | sed -n 's/^part\.[^.]*\.files=\([0-9]*\)$/\1/p' | awk '{s+=$1} END {print s+0}')"
ps_whole="$(field files "$TMP/pskill")"
[ "$ps_sum" -ge "$ps_whole" ] \
  || fail "partition lost files: parts sum to $ps_sum, whole is $ps_whole"
[ "$ps_sum" -gt "$ps_whole" ] \
  || fail "parts were measured under the parent's rules: sum $ps_sum equals the parent's $ps_whole, so the skill parts' markdown is still invisible"

# ── A skill is markdown, and Step 1 has to be able to see one ────────────────
# .md is not a source extension, so pointing the resolver at skills/aidex-review
# returned 1 file: SKILL.md and references/01-review-angles.md -- 487 lines and all of
# the substance -- were invisible, and the file set for the review of these two skills
# had to be assembled by hand. Step 1 is described as never-skip and for this whole
# class of target it could not run.
#
# A flag and a detection, not a widened SOURCE_EXT: pulling every .md into a normal
# app's review is noise a correctness finder would spend its budget on.
mkdir -p "$TMP/askill/references" "$TMP/askill/scripts"
printf -- '---\nname: askill\n---\n\n# A skill\n' > "$TMP/askill/SKILL.md"
printf '# Angles\n\ncontent\n' > "$TMP/askill/references/01-angles.md"
printf 'echo hi\n' > "$TMP/askill/scripts/do.sh"

# 24. A directory carrying a SKILL.md IS a skill, and its markdown is its source.
[ "$(field skill_target "$TMP/askill")" = "yes" ] \
  || fail "a directory with SKILL.md must be detected as a skill target, got '$(field skill_target "$TMP/askill")'"
[ "$(field files "$TMP/askill")" = "3" ] \
  || fail "a skill target must resolve its markdown (SKILL.md + reference + script = 3), got $(field files "$TMP/askill")"
run --files "$TMP/askill" | grep -q 'SKILL.md' || fail "SKILL.md is missing from a skill target's file set"
run --files "$TMP/askill" | grep -q '01-angles.md' || fail "the skill's reference is missing from its file set"

# 25. ...and on anything else markdown stays out unless asked for. `notes` in the mod
#     fixture is a README: a correctness finder reading it is budget that never reached
#     the code.
[ "$(field skill_target "$TMP/mod")" = "no" ] || fail "a normal module must not be read as a skill target"
run --files "$TMP/mod" | grep -q 'README.md' && fail "markdown leaked into a normal module's file set"
run --files --include-docs "$TMP/mod" | grep -q 'README.md' \
  || fail "--include-docs must bring markdown into the reviewed set"
[ "$(field include_docs --include-docs "$TMP/mod")" = "1" ] || fail "--include-docs must be reported in the measurement"

# ── Prose lockstep: SKILL.md and the angle catalog ───────────────────────────
# Cell 11 asserts the resolver's key name against SKILL.md and stops there, which is
# why the catalog could drift behind SKILL.md through four commits that all edited
# SKILL.md (5129808 names this in its own message). These two cells put the catalog in
# the site list.
SKILL_MD="$SCRIPT_DIR/../SKILL.md"
ANGLES="$SCRIPT_DIR/../references/01-review-angles.md"
# The catalog's verify section only — a token elsewhere in the file is not the copy.
verify_section() { awk '/^## The verify phase/{f=1;next} f && /^## /{exit} f' "$ANGLES"; }

# 26. The verifier's return shape has ONE owner. SKILL.md Step 3.3 is it — the
#     always-loaded execution surface — so if SKILL.md defines a return field, the
#     catalog must either carry it too or say where it lives. What it must not do is
#     state the contract as if complete while missing fields, which is what it did:
#     three verdicts and no severity override, no PLAUSIBLE reason, and no marker
#     saying it was partial. A prompt authored from the catalog then omits them.
VERIFY="$(verify_section)"
case "$VERIFY" in *"Step 3.3"*) DEFERS=1 ;; *) DEFERS=0 ;; esac
for tok in 'unreachable-trigger' 'undetermined' 'severity'; do
  if grep -q -- "$tok" "$SKILL_MD"; then
    case "$VERIFY" in
      *"$tok"*) : ;;
      *) [ "$DEFERS" -eq 1 ] \
           || fail "SKILL.md defines the verifier field '$tok'; the catalog's verify section neither carries it nor defers to Step 3.3" ;;
    esac
  fi
done

# 27. The catalog pointer is an INSTRUCTION, at the step that needs it. skill-conventions
#     measured the two forms over 58 (skill, reference) pairs on 2026-08-05: imperative +
#     absolute path + stated cost read 80.6% of the time, `See [file](relative)` in a
#     header block 0%. This skill's body then demands catalog content three times — the
#     angle names, the verbatim scope boundary, the finder cap — so a pointer nobody
#     follows means finders launched with no scope boundary and invented angle names,
#     with nothing erroring.
PTR_LINE="$(grep -n 'Read `~/.claude/skills/aidex-review/references/01-review-angles.md`' "$SKILL_MD" | head -1 | cut -d: -f1)"
STEP_LINE="$(grep -n '^## Step 1' "$SKILL_MD" | head -1 | cut -d: -f1)"
[ -n "$PTR_LINE" ] \
  || fail "SKILL.md has no imperative absolute-path pointer to the angle catalog (the form measured at 80.6% read)"
[ -n "$PTR_LINE" ] && [ -n "$STEP_LINE" ] && [ "$PTR_LINE" -gt "$STEP_LINE" ] \
  || fail "the catalog pointer is not inside the numbered workflow — a header-block citation is the 0%-read form"
grep -q '](references/01-review-angles.md)' "$SKILL_MD" \
  && fail "SKILL.md still carries the bare repo-relative markdown link to the catalog — a second, weaker citation"

# 28. The sizing rule has one owner and it is the resolver — SKILL.md Step 1 narrates it
#     operationally. The catalog restated it and went stale: it read "sets the finder
#     count from the target's LOC" while the resolver had moved to SOURCE_LOC, and stood
#     wrong through four commits. A catalog of angles is the wrong altitude for resolver
#     mechanics. Flattened before matching, because the stale copy wrapped mid-phrase
#     and a line-anchored grep for it passed over the very sentence it was written to
#     catch.
ANGLES_FLAT="$(tr '\n' ' ' < "$ANGLES" | tr -s ' ')"
for pat in 'small 2 / medium 3 / large 4' 'clamped to' '--partition'; do
  case "$ANGLES_FLAT" in
    *"$pat"*) fail "the angle catalog re-derives resolver mechanics ('$pat') — resolve-review-target.sh owns them" ;;
  esac
done

# 29. The 17x measurement lives at three sites and is explicitly n=1 and explicitly
#     computed under a superseded sizing rule, so it WILL be re-measured. Nothing
#     pointed from any site to any other, so the second measurement would land in one
#     of them and the skill would quote two ratios for the same run. The reference's
#     Cost section owns the provenance; the other two name it.
grep -q '01-review-angles.md` § Cost' "$SKILL_MD" \
  || fail "SKILL.md's cost paragraph does not point at the Cost section that owns the measurement"
grep -q '01-review-angles.md' "$RESOLVER" \
  || fail "the resolver quotes the 17x figure without naming the section that owns it"

# 30. The README is a lockstep site, because it is the only description of this skill
#     a reader outside the repo ever sees. 27d0ce5 replaced the oversize wall with
#     `--partition`; the README row still read "Refuses an oversize target instead of
#     sampling it", and the next day the owner read that row and re-litigated a
#     decision already settled in his favour. 4d8e97d fixed the line and added no
#     guard — while db45759, hours earlier, had added README.md as lockstep site 7 for
#     the audit playbook registry. The repo knew this failure class and guarded a
#     different skill with it.
#
#     One direction only: IF the row claims refusal, it must also name --partition.
#     A row that never mentions refusing is not this skill's row to police.
#     Skipped when the README is absent — install.sh ships no README, so an
#     unconditional read FAILs from the installed ~/.aidex/ tree (db45759's idiom).
README="$SCRIPT_DIR/../../../README.md"
if [ -f "$README" ]; then
  ROW="$(grep -F '| **`aidex-review`**' "$README" | head -1)"
  if [ -z "$ROW" ]; then
    fail "the README has no aidex-review row — the public description of this skill vanished"
  else
    case "$ROW" in
      *refus*|*Refus*)
        case "$ROW" in
          *--partition*) : ;;
          *) fail "the README says aidex-review refuses an oversize target but never names --partition — that is the inverted claim 27d0ce5 made false and 4d8e97d corrected" ;;
        esac ;;
      *) : ;;
    esac
  fi
else
  echo "  skip: no README at $README (installed tree) — cell 30 not exercised"
fi

if [ "$FAILURES" -eq 0 ]; then
  echo "OK — resolve-review-target: 34 cells (3 refusals, 2 exclusions, 3 measurements, 2 bounds, 1 cost-floor lockstep, 4 test-vs-source, 3 depth-override, 9 partition, 2 doc-target, 5 prose lockstep)"
  exit 0
fi
echo "FAIL — $FAILURES cell(s)"
exit 1
