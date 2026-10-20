#!/usr/bin/env bash
# test-references-pinned.sh — content moved out of SKILL.md keeps an owner and a pointer.
#
# A split that loses its pointer, or a pointer in the "See ..." shape, is read 0% of the
# time (BL-125); a reference that loses a phase drifts silently. Each cell pins one side.
set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SKILL="$SKILL_DIR/SKILL.md"
REF="$SKILL_DIR/references/03-skeleton-first.md"
HARNESS="$SKILL_DIR/references/01-harness-contract.md"
FAILURES=0
fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }

# 1. SKILL.md points at the skeleton reference as an imperative Read with the full path.
grep -A1 'Read$' "$SKILL" | grep -qF '`${CLAUDE_PLUGIN_ROOT}/skills/ui-contract/references/03-skeleton-first.md`' \
  || fail "SKILL.md lacks the imperative Read pointer to references/03-skeleton-first.md"

# 2. The reference owns all five phases, in order.
prev=0
for phase in "1. **Skeleton of the real page**" "2. **Review of the skeleton**" \
             "3. **Shared primitives**" "4. **Gallery and gate**" "5. **Wire**"; do
  n="$(grep -nF "$phase" "$REF" | head -1 | cut -d: -f1)"
  if [ -z "$n" ]; then fail "03-skeleton-first.md lacks phase: $phase"; continue; fi
  [ "$n" -gt "$prev" ] || fail "phase out of order: $phase"
  prev="$n"
done

# 3. The rules that moved with the phases are still stated; the round shape stays inline
#    because it is sketch-trial text.
grep -qF 'Geometry assertions go in before the first owner round' "$REF" || fail "geometry-assertion rule lost"
# The documented pending-owner line, filled in, is read by the gate that owns the grammar.
LINE="$(python3 -c "
import re, sys
t = ' '.join(open(sys.argv[1], encoding='utf-8').read().split())
m = re.search(r'\`(ui-surface: [^\`]*pending-owner[^\`]*)\`', t)
print(m.group(1).replace('<N>', '3').replace('<its page>', 'consult.html').replace('...', 'empty') if m else '')
" "$REF")"
PLAN="$(mktemp)"; printf '## UI contract\n\n## Execution log\n\n- %s\n' "$LINE" > "$PLAN"
bash "$SKILL_DIR/../plan-exec/scripts/check-ui-evidence.sh" --pending "$PLAN" 2>&1 | grep -qxF 'pending-owner: phase 3 · consult.html · cells: empty' \
  || fail "the pending-owner line documented in 03-skeleton-first.md is not read by check-ui-evidence.sh --pending: '$LINE'"
rm -f "$PLAN"
grep -qF 'a budget of 2 rounds' "$SKILL" || fail "skeleton round budget left SKILL.md"

# 4. The light/dark-only rule moved to the harness contract; SKILL.md points there.
grep -qF 'Light and dark are the only two modes this contract renders' "$HARNESS" || fail "light/dark rule missing from harness contract"
grep -qF 'harness contract § 3' "$SKILL" || fail "SKILL.md lost its pointer to harness contract § 3"

# 5. BL-818: the harness mocks background pollers (activity badge) by default, so a gallery
#    spec carries no per-spec copy; the contract states it as a property of the harness.
grep -qF 'Background pollers are mocked by the harness by default' "$HARNESS" \
  || fail "harness contract lost the default poller-mock rule (BL-818)"
grep -qF 'keeps its per-spec copy' "$HARNESS" \
  || fail "harness contract lost the keep-the-copy-until-installed condition (BL-818)"
grep -qF 'overrides the default with its own' "$HARNESS" \
  || fail "harness contract lost the poller override clause (BL-818)"
grep -qF 'cannot reach' "$HARNESS" \
  || fail "harness contract lost the server-fetched poller volatile-region clause (BL-818)"

# 6. Staged rounds (2026-10-20): a cell left `deferred:` is a decision never made. The kit
#    says hardening refuses it; verify-ui is what runs at hardening, so it must count it failed.
VERIFY_UI="$SKILL_DIR/../../agents/verify-ui.md"
grep -qF "reason: 'deferred:" "$SKILL_DIR/references/02-sketch-round-kit.md" || fail "kit lost the deferred-cell declaration"
grep -qF 'deferred:' "$VERIFY_UI" && grep -qF 'counted in `<f>`' "$VERIFY_UI" \
  || fail "verify-ui does not count a deferred: cell as failed"

# 7. A declared not-applicable skip ("<state> — not applicable: <reason>", an unconditional
#    test.skip in the gallery) is not a failure: counting it in <f> would fail every gallery
#    that declares an absent cell. A deferred: reason is the exception (cell 6); any other skip counts.
#    Read whitespace-normalised, like cell 3, and with the exemption tied to the title shape in
#    one span: a reversed sentence ("both counted in") must fail, not only a deleted one.
python3 - "$VERIFY_UI" <<'PY' || fail "verify-ui does not leave a declared not-applicable skip out of <f>, count a deferred: one once whatever its case, and every other skip"
import re, sys
t = ' '.join(open(sys.argv[1], encoding='utf-8').read().split())
need = [
    r'A skip is none of those in two cases, both left out of `<f>`.{0,400}?`<state> — not applicable: <reason>`',
    r'not applicable: <reason>`.{0,200}?unless that reason, ignoring case and leading spaces, starts with `deferred:`',
    r'counted once, by step 6',
    r'Any other skip counts in `<f>`',
    r'reason that starts, ignoring case and leading spaces, with `deferred:`',
]
sys.exit(0 if all(re.search(n, t) for n in need) else 1)
PY

if [ "$FAILURES" -eq 0 ]; then echo "PASS: ui-contract references pinned"; exit 0; fi
echo "FAIL: $FAILURES cell(s)"; exit 1
