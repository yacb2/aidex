#!/usr/bin/env bash
# test-sweep-reference-reads.sh — LOOP-013 w1-ur2 audit-c09: the reference sweep must
# see plugin-fired skills and must not credit a read to the wrong skill.
#
# Layer: script over a synthetic skills dir and transcript root under mktemp. The
# failure is a silent zero ("0 pairs ... 0 NEVER read", rc 0), so it is observable
# only by running the script.
#   (a) a Skill call named `aidex:alpha` counts as a firing of skill `alpha`
#   (b) a read of beta/references/shared.md is NOT credited to alpha's
#       alpha/references/shared.md citation (bare-basename over-credit)
#   (d) no firing at all is refused
#   (c) a read of alpha/references/shared.md IS credited to alpha
#   (f) audit-s24: mine-reference-reads --when-skill takes the bare name the way the sweep
#       does, so `--when-skill alpha` finds the sessions that fired `aidex:alpha`
#
# Run with: bash skills/audit/tests/test-sweep-reference-reads.sh

set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SWEEP="$TESTS_DIR/../scripts/sweep-reference-reads.py"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/skills/alpha" "$W/skills/beta" "$W/tx/-Users-u-Documents-projects-p"
printf 'See [x](references/shared.md)\n' > "$W/skills/alpha/SKILL.md"
printf 'See [x](references/shared.md)\n' > "$W/skills/beta/SKILL.md"

python3 - "$W/tx/-Users-u-Documents-projects-p" <<'PY'
import json, sys
d = sys.argv[1]
def sess(name, skill, read_path):
    lines = [{"type": "assistant", "message": {"content": [
        {"type": "tool_use", "name": "Skill", "input": {"skill": skill}},
        {"type": "tool_use", "name": "Read", "input": {"file_path": read_path}}]}}]
    open(f"{d}/{name}.jsonl", "w").write("\n".join(json.dumps(l) for l in lines) + "\n")
# alpha fires, reads only BETA's shared.md
sess("a", "aidex:alpha", "/x/skills/beta/references/shared.md")
# alpha fires again and reads its own
sess("b", "aidex:alpha", "/x/skills/alpha/references/shared.md")
# another plugin's skill of the same bare name must not count as alpha
sess("c", "other:alpha", "/x/skills/alpha/references/shared.md")
PY

# audit-c34: a transcript line that is not JSON is counted and reported, never dropped silently
printf 'not json\n{"truncated":\n' >> "$W/tx/-Users-u-Documents-projects-p/b.jsonl"

out="$(python3 "$SWEEP" --skills-dir "$W/skills" --projects-root "$W/tx" --min-fired 1 2>&1)"
grep -qE '^2 unparseable' <<<"$out" || fail "(e) expected a count of 2 unparseable lines: $out"
grep -qE '^alpha +shared\.md +2 +1 ' <<<"$out" \
  || fail "(a)(b)(c) expected alpha/shared.md fired 2, read 1 (own read only): $out"
grep -qE '^beta ' <<<"$out" \
  && fail "beta never fired and must not appear: $out"

#   (d) a corpus where no cited skill fired is an error, not "0 NEVER read"
mkdir -p "$W/empty/-Users-u-Documents-projects-p"
out_d="$(python3 "$SWEEP" --skills-dir "$W/skills" --projects-root "$W/empty" 2>&1)"; rc_d=$?
[[ $rc_d -ne 0 ]] || fail "(d) no firings must exit non-zero, got rc=0: $out_d"
grep -q 'NEVER read' <<<"$out_d" && fail "(d) no firings must not print a clean count: $out_d"

#   (e2) a corpus of nothing but a bad line: the count still reaches stderr and --json
mkdir -p "$W/bad/-Users-u-Documents-projects-p"
printf 'not json\n' > "$W/bad/-Users-u-Documents-projects-p/x.jsonl"
out_e="$(python3 "$SWEEP" --skills-dir "$W/skills" --projects-root "$W/bad" --json "$W/bad.json" 2>&1)"
grep -qE '^1 unparseable' <<<"$out_e" || fail "(e2) expected '1 unparseable' before the no-firing exit: $out_e"
[[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("skipped"))' "$W/bad.json" 2>&1)" == 1 ]] \
  || fail "(e2) --json lacks skipped == 1"

#   (f) mine-reference-reads: the Skill tool records `aidex:alpha`; --when-skill alpha must match it.
#       Its corpus root is ~/.claude/projects, so HOME points at the fixture.
mkdir -p "$W/home/.claude/projects"
cp -R "$W/tx/-Users-u-Documents-projects-p" "$W/home/.claude/projects/"
out_f="$(HOME="$W/home" python3 "$TESTS_DIR/../scripts/mine-reference-reads.py" alpha/references/shared.md --when-skill alpha 2>&1)"
grep -q 'no sessions in scope' <<<"$out_f" \
  && fail "(f) --when-skill alpha found no session although aidex:alpha fired: $out_f"
grep -qE '^alpha +2 +1$' <<<"$out_f" \
  || fail "(f) expected alpha: 2 in scope, 1 read (the other-plugin other:alpha firing is not alpha): $out_f"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — sweep-reference-reads: aidex:<skill> firings counted, a read is credited only to the skill whose references/ folder it came from"
