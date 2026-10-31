#!/usr/bin/env bash
# Rendered-size regression for test_skill_budget.sh.
#
# Regression this locks (superpowers-adoptions phase 01, measurement m18): Claude Code
# re-attaches a skill after compaction cut at 20,000 characters of the RENDERED text
# (body without front matter, ${CLAUDE_PLUGIN_ROOT} / ${CLAUDE_SKILL_DIR} expanded, plus the
# "Base directory for this skill:" header). The gate measured the raw body, so plan-exec
# (20,161 rendered) and ui-contract (20,135) passed while being cut on every compaction.
#
# Each case builds a synthetic skill in a throwaway tree that holds a copy of the gate under
# test, calibrates the padding from the gate's own "rendered N" line, and checks the verdict:
#   raw body < 19,900 but rendered > 19,900  -> must FAIL (the bug)
#   rendered == 19,900                       -> must pass (boundary, margin 0)
#   rendered == 19,901                       -> must FAIL (boundary + 1)
#   small skill                              -> must pass and print a margin line
#
# Run with: bash skills/conventions/scripts/test_skill_budget_rendered.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
failures=0
check() { # check <label> <expected-exit-zero|nonzero> <actual-rc>
  local ok=0
  [[ "$2" == zero && "$3" -eq 0 ]] && ok=1
  [[ "$2" == nonzero && "$3" -ne 0 ]] && ok=1
  if (( ok )); then printf 'ok   %s\n' "$1"; else printf 'FAIL %s (expected %s exit, got %s)\n' "$1" "$2" "$3"; failures=$((failures + 1)); fi
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/skill-budget.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/skills/conventions/scripts" "$tmp/skills/conventions/references"
cp "$SCRIPT_DIR/test_skill_budget.sh" "$SCRIPT_DIR/_owned-skills.sh" "$tmp/skills/conventions/scripts/"
cp "$SCRIPT_DIR/../references/skill-conventions.md" "$tmp/skills/conventions/references/"
gate="$tmp/skills/conventions/scripts/test_skill_budget.sh"
mkdir -p "$tmp/skills/synth"

# write_synth <pad-chars> <var-uses>: front matter, <var-uses> lines with the variable, padding.
write_synth() { # optional third arg: variable name (default CLAUDE_SKILL_DIR)
  local var="${3:-CLAUDE_SKILL_DIR}"
  {
    printf -- '---\nname: synth\ndescription: synthetic\n---\n\n'
    local i
    for ((i = 0; i < $2; i++)); do printf 'Read `${%s}/references/01-x.md` first.\n' "$var"; done
    (( $1 > 0 )) && head -c "$1" /dev/zero | tr '\0' 'x'
    printf '\n'
  } > "$tmp/skills/synth/SKILL.md"
}
# gate_fails_rendered: the gate exits nonzero AND says the rendered-size limit is why (a token or
# line failure must not stand in for it).
gate_fails_rendered() { local o; o="$(bash "$gate" 2>&1)"; local rc=$?; (( rc != 0 )) && grep -q '^FAIL: synth: rendered ' <<<"$o"; }
rendered_of() { LC_ALL=C bash "$gate" 2>&1 | sed -n 's/^synth: rendered \([0-9]*\),.*/\1/p'; }

# Case 1: raw body ~19,000 bytes (under the gate) that renders over it through 30 expansions.
write_synth 17400 30
raw="$(sed '1,/^---$/{/^---$/!d;}' "$tmp/skills/synth/SKILL.md" | tail -n +3 | wc -c)"
(( raw < 19900 )) || { echo "FAIL setup: raw body $raw is not under 19,900"; exit 1; }
gate_fails_rendered; check "raw $raw < 19,900 but rendered over: gate fails on the rendered limit" zero $?

# Case 2/3: exact boundary, calibrated from the gate's own rendered figure.
write_synth 100 3
base="$(rendered_of)"
[[ "$base" =~ ^[0-9]+$ ]] || { echo "FAIL setup: gate printed no 'synth: rendered N' line"; exit 1; }
write_synth $((100 + 19900 - base)) 3
out="$(bash "$gate" 2>&1)"; rc=$?
check "rendered exactly 19,900: gate passes" zero $rc
grep -q '^synth: rendered 19900, margin 0$' <<<"$out" || { echo "FAIL boundary line missing: $(grep '^synth:' <<<"$out")"; failures=$((failures + 1)); }
write_synth $((100 + 19901 - base)) 3
gate_fails_rendered; check "rendered 19,901: gate fails on the rendered limit" zero $?

# Case 3b: ${CLAUDE_PLUGIN_ROOT} is expanded too (padding for 30 uses that fit raw, not rendered).
write_synth 17400 30 CLAUDE_PLUGIN_ROOT
gate_fails_rendered; check "only CLAUDE_PLUGIN_ROOT expansion pushes over: gate fails on the rendered limit" zero $?

# Case 3c: the "Base directory for this skill: <path>" header is counted (an empty body still renders it).
write_synth 0 0
hdr="$(rendered_of)"
(( hdr > 80 )) && check "empty body still renders the header ($hdr chars)" zero 0 || check "empty body still renders the header ($hdr chars)" zero 1

# Case 4: small skill passes and prints its margin.
write_synth 100 3
out="$(bash "$gate" 2>&1)"; rc=$?
check "small skill: gate passes" zero $rc
grep -qE '^synth: rendered [0-9]+, margin [0-9]+$' <<<"$out" || { echo "FAIL no margin line for synth"; failures=$((failures + 1)); }

# Case 5 (independent value): a synth with no variables; the expected size is computed here in
# python from the file itself (header + body after the closing fence, trailing newlines trimmed
# plus one), never from the gate. A non-ASCII char counts once, not once per byte.
plugin_root="$(sed -n 's/^RENDER_PLUGIN_ROOT="\(.*\)"$/\1/p' "$gate")"
expected_of() { python3 -I - "$tmp/skills/synth/SKILL.md" "$plugin_root" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", newline="").read().replace("\r\n", "\n")
lines = text.split("\n")
if lines[0] == "---":
    end = lines.index("---", 1)
    body = "\n".join(lines[end + 1:])
else:
    body = text
body = body.rstrip("\n")
print(len("Base directory for this skill: %s/skills/synth\n\n" % sys.argv[2]) + len(body) + 1)
PY
}
printf -- '---\nname: synth\ndescription: synthetic\n---\n\nplain body, no variables\nsecond line\n' > "$tmp/skills/synth/SKILL.md"
want="$(expected_of)"; got="$(rendered_of)"
[[ -n "$want" && "$got" == "$want" ]]; check "independent size: gate printed $got, python computed $want" zero $?

# Case 6: one em dash is one character, not three bytes (run under the C locale on purpose: the
# gate must count characters whatever locale the caller has).
printf -- '---\nname: synth\ndescription: synthetic\n---\n\nplain body, no variables\nsecond line x\n' > "$tmp/skills/synth/SKILL.md"
plain="$(rendered_of)"
printf -- '---\nname: synth\ndescription: synthetic\n---\n\nplain body, no variables\nsecond line \xe2\x80\x94\n' > "$tmp/skills/synth/SKILL.md"
dash="$(rendered_of)"
(( ${dash:-0} - ${plain:-0} == 0 )); check "an em dash counts as the one character it replaces (plain $plain, dashed $dash)" zero $?

# Case 7: '---' lines in the body count (4 characters each: three dashes and the newline).
write_synth 100 3; base0="$(rendered_of)"
{ printf -- '---\nname: synth\ndescription: synthetic\n---\n\n'; for i in 1 2 3 4 5; do printf -- '---\n'; done; head -c 100 /dev/zero | tr '\0' 'x'; printf '\n'
  for i in 1 2 3; do printf 'Read `${CLAUDE_SKILL_DIR}/references/01-x.md` first.\n'; done; } > "$tmp/skills/synth/SKILL.md"
five="$(rendered_of)"
(( ${five:-0} - ${base0:-0} == 20 )); check "5 body '---' lines add exactly 20 characters ($base0 -> $five)" zero $?

# Case 8: CRLF fences are front matter too, so a CRLF skill over the limit fails on the rendered limit.
{ printf -- '---\r\nname: synth\r\ndescription: synthetic\r\n---\r\n\r\n'; head -c 20000 /dev/zero | tr '\0' 'x'; printf '\r\n'; } > "$tmp/skills/synth/SKILL.md"
gate_fails_rendered; check "CRLF skill over 19,900: gate fails on the rendered limit" zero $?
{ printf -- '---\r\nname: synth\r\ndescription: synthetic\r\n---\r\n\r\n'; head -c 100 /dev/zero | tr '\0' 'x'; printf '\r\n'; } > "$tmp/skills/synth/SKILL.md"
crlf_small="$(rendered_of)"
printf -- '---\nname: synth\ndescription: synthetic\n---\n\n%s\n' "$(head -c 100 /dev/zero | tr '\0' 'x')" > "$tmp/skills/synth/SKILL.md"
lf_small="$(rendered_of)"
(( ${crlf_small:-0} - ${lf_small:-0} == 2 )); check "CRLF front matter is stripped (CRLF $crlf_small vs LF $lf_small, only the 2 CRs of the body differ)" zero $?

# Case 9: a file with no front matter counts as a whole, so it fails over the limit.
{ printf '# no front matter\n'; head -c 20000 /dev/zero | tr '\0' 'x'; printf '\n'; } > "$tmp/skills/synth/SKILL.md"
gate_fails_rendered; check "no-front-matter skill over 19,900: gate fails on the rendered limit" zero $?

(( failures == 0 )) && { echo "OK - rendered-size gate behaves"; exit 0; }
echo "$failures failure(s)"; exit 1
