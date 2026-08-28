#!/usr/bin/env bash
# test-playbook-type-lockstep.sh — the set of audit types is declared in five places and
# they say the same thing.
#
# `AUDIT_TYPES` in scripts/_lib.sh is the runtime enum: normalize_type() accepts nothing
# outside it, so it is the owner and every other site is a copy. The copies drift the way
# copies do — when rule-ablation shipped it reached the header comment of new-audit.sh and
# not its usage text, so `/aidex-audit new` printed a list of valid types missing one it
# accepts. 04-playbooks.md carried the same drift as prose counts: "Nine stock audit
# types" and "If none of the eight fits" over a table of ten (BL-160).
#
# Sites:
#   1. scripts/_lib.sh                      AUDIT_TYPES=(...)          [owner]
#   2. assets/templates/methodology/        one <type>.md.template each
#   3. scripts/new-audit.sh                 the `<type>:` header comment
#   4. scripts/new-audit.sh                 the "Types:" usage line
#   5. SKILL.md                             ### Supported audit types
#   6. references/04-playbooks.md           the picker table
#   7. README.md                            the aidex-audit row          [public]
#   8. aidex-conventions/SKILL.md           the audits tier summary
#   9. aidex-conventions/audit-conventions.md   the methodology table
#
# Sites 7-9 are outside this skill and are checked here anyway, because the enum is one
# thing and the drift does not respect directories: the README's count was already fixed
# once for this exact reason (647ced1, 2026-07-05, "Ships 7 playbooks") and had drifted
# twice more by the time this guard was written.
#
# Run: bash skills/aidex-audit/tests/test-playbook-type-lockstep.sh
# Exit: 0 if all nine agree.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$DIR/scripts/_lib.sh"
NEW="$DIR/scripts/new-audit.sh"
SKILL="$DIR/SKILL.md"
PLAYBOOKS="$DIR/references/04-playbooks.md"
TPL_DIR="$DIR/assets/templates/methodology"
REPO="$(cd "$DIR/../.." && pwd)"
README="$REPO/README.md"
CONV_SKILL="$REPO/skills/aidex-conventions/SKILL.md"
CONV_AUDIT="$REPO/skills/aidex-conventions/references/audit-conventions.md"

PASS=0
FAIL=0

# `custom` is a type with no playbook: new-audit.sh names the methodology folder after the
# slug and falls through to the generic 00-methodology.md template. It is the one
# asymmetry between the enum and the directory, so it is subtracted once, here, by name —
# never as a count adjustment in two places.
NO_TEMPLATE="custom"

norm() { tr ' ' '\n' | tr -d '`·,' | grep -vE '^$' | sort -u; }

# <label> <expected-set> <actual-set>
compare() {
  local label="$1" a b d
  a="$(printf '%s\n' "$2" | sort -u)"
  b="$(printf '%s\n' "$3" | sort -u)"
  d="$(comm -3 <(printf '%s\n' "$a") <(printf '%s\n' "$b"))"
  if [[ -z "$d" ]]; then
    printf '  ok: %s\n' "$label"; PASS=$((PASS+1))
  else
    printf '  FAIL: %s\n' "$label"; FAIL=$((FAIL+1))
    printf '    (left column: expected only · right column: found only)\n'
    printf '%s\n' "$d" | sed 's/^/    /'
  fi
}

# <label> <condition>
check() {
  if eval "$2"; then printf '  ok: %s\n' "$1"; PASS=$((PASS+1))
  else printf '  FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); fi
}

# --- site 1: the owner ------------------------------------------------------------
CANON="$(sed -n 's/^AUDIT_TYPES=(\(.*\))$/\1/p' "$LIB" | norm)"
# An unreadable owner makes every comparison below vacuous: two empty sets agree.
check "AUDIT_TYPES is readable from _lib.sh (got $(wc -w <<<"$CANON" | tr -d ' ') types)" \
      '[[ "$(wc -w <<<"$CANON" | tr -d " ")" -ge 5 ]]'
CANON_TPL="$(grep -v "^${NO_TEMPLATE}$" <<<"$CANON")"

# --- site 2: what actually ships -------------------------------------------------
SHIPPED="$(cd "$TPL_DIR" && ls -1 ./*.md.template | sed 's|^\./||; s|\.md\.template$||' | sort -u)"
compare "every type in AUDIT_TYPES ships a playbook (except $NO_TEMPLATE)" "$CANON_TPL" "$SHIPPED"

# --- sites 3 and 4: what new-audit.sh tells the caller ---------------------------
# Both wrap across lines, so flatten before matching — a guard that greps one physical
# line of a wrapped list passes on whatever fell onto the next one.
FLAT_NEW="$(tr '\n' ' ' < "$NEW" | tr -s ' ')"
HDR_TYPES="$(sed -E 's/.*#[[:space:]]*<type>:[[:space:]]*//; s/\(.*//' <<<"$FLAT_NEW" | sed 's/#//g' | norm)"
compare "new-audit.sh's <type> comment lists AUDIT_TYPES" "$CANON" "$HDR_TYPES"

USAGE_TYPES="$(sed -E 's/.*Types:[[:space:]]*//; s/\(legacy.*//' <<<"$FLAT_NEW" | norm)"
compare "new-audit.sh's usage text lists AUDIT_TYPES" "$CANON" "$USAGE_TYPES"

# --- site 5: SKILL.md ------------------------------------------------------------
FLAT_SKILL="$(tr '\n' ' ' < "$SKILL" | tr -s ' ')"
SKILL_TYPES="$(sed -E 's/.*### Supported audit types \(for `new`\)[[:space:]]*//; s/ — .*//' <<<"$FLAT_SKILL" | norm)"
compare "SKILL.md's supported-types list is AUDIT_TYPES" "$CANON" "$SKILL_TYPES"

# --- site 6: the picker table ----------------------------------------------------
# 04-playbooks.md is the index a reader consults to choose a type, so a shipped playbook
# missing from the table is one nobody picks. `custom` has no row by design: it is reached
# from the prose line under the decision flow, not from the table.
TABLE_TYPES="$(grep -oE '^\| \[[a-z0-9-]+\]' "$PLAYBOOKS" | tr -d '|[] ' | sort -u)"
compare "04-playbooks.md's table has a row per shipped playbook" "$SHIPPED" "$TABLE_TYPES"
check "04-playbooks.md still points at $NO_TEMPLATE outside the table" \
      "grep -q '\`$NO_TEMPLATE\`' '$PLAYBOOKS'"

# --- sites 7-9: the copies outside this skill ------------------------------------
# Only reachable from a repo checkout: install.sh ships skills/ and rules/, not README.md,
# so in the installed ~/.claude/skills/ tree these three are absent. Skipping is printed, never counted as a pass.
PROSE_SITES=("$PLAYBOOKS")
if [[ -f "$README" && -f "$CONV_SKILL" && -f "$CONV_AUDIT" ]]; then
  PROSE_SITES+=("$README" "$CONV_SKILL" "$CONV_AUDIT")

  # README and aidex-conventions/SKILL.md each summarize the set as a parenthesized list
  # after the word "playbooks". Flatten first — both sentences wrap.
  paren_list() { tr '\n' ' ' < "$1" | tr -s ' ' | grep -oE 'playbooks \([^)]*\)' | tr -d '()' | sed 's/^playbooks //' | norm; }
  compare "README.md lists every shipped playbook" "$SHIPPED" "$(paren_list "$README")"
  compare "aidex-conventions/SKILL.md lists every shipped playbook" "$SHIPPED" "$(paren_list "$CONV_SKILL")"

  # audit-conventions.md carries the methodology table aidex-audit calls "the full
  # convention". Bounded by its own heading sentence and the custom-methodology line, so
  # another table in that file cannot answer for it.
  CONV_TYPES="$(awk '/AIDEX ships playbook templates/{f=1; next} f&&/^Custom methodologies/{exit} f&&/^\| `/{print}' "$CONV_AUDIT" \
                | grep -oE '^\| `[a-z0-9-]+`' | tr -d '|` ' | sort -u)"
  compare "audit-conventions.md's methodology table is the shipped set" "$SHIPPED" "$CONV_TYPES"
else
  printf '  skip: sites 7-9 (README.md, aidex-conventions) — not a repo checkout\n'
fi

# --- no count of the types spelled in prose --------------------------------------
# The lists are machine-checked above; a number written out beside one is not, and every
# such number in this repo has gone stale. README's went stale twice after 647ced1 fixed
# it. The fix is to state no count at all: the list is what says how many.
NUM='(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|[0-9]+)'
for site in "${PROSE_SITES[@]}"; do
  FLAT_SITE="$(tr '\n' ' ' < "$site" | tr -s ' ')"
  COUNTS="$(grep -oiE "\b$NUM\b stock audit types|none of the \b$NUM\b|\b$NUM\b (ready-made |stock )?playbooks" <<<"$FLAT_SITE")"
  check "$(basename "$site"): states no count of the playbooks it lists" '[[ -z "$COUNTS" ]]'
  [[ -n "$COUNTS" ]] && printf '    %s\n' "$COUNTS"
done

printf '\nplaybook type lockstep: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
