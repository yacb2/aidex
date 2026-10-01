#!/usr/bin/env bash
# test-open-decisions-section.sh — the OPTIONAL `## Open decisions` section (BL-429).
#
# Two properties, and the second is the one that keeps the section optional:
#   1. plan-conventions.md documents the section, marks it optional, names the three
#      unblockers (research / prototype / owner conversation), and says it is not
#      required for direct or scoped plans.
#   2. validate.py accepts a plan WITH the section and a plan WITHOUT it — the section
#      is documentation, never a validator requirement, so neither fixture may produce
#      a violation.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CANON="$HERE/../../conventions/references/plan-conventions.md"
VALIDATE="$HERE/../../conventions/scripts/validate.py"

pass=0; fail=0
check() { if eval "$2"; then echo "  ok: $1"; pass=$((pass+1)); else echo "  FAIL: $1"; fail=$((fail+1)); fi; }

[[ -f "$CANON" ]] || { echo "FAIL: canon not found at $CANON" >&2; exit 1; }
[[ -f "$VALIDATE" ]] || { echo "FAIL: validate.py not found at $VALIDATE" >&2; exit 1; }

echo "plan-conventions.md documents the section:"
check "carries an '## Open decisions' section" \
  "grep -q '^## Open decisions' '$CANON'"
check "the section is marked optional" \
  "awk '/^## Open decisions/,/^## [^O]/' '$CANON' | grep >/dev/null -i 'optional'"
check "names research as an unblocker" \
  "awk '/^## Open decisions/,/^## [^O]/' '$CANON' | grep >/dev/null 'research'"
check "names prototype as an unblocker" \
  "awk '/^## Open decisions/,/^## [^O]/' '$CANON' | grep >/dev/null 'prototype'"
check "names owner conversation as an unblocker" \
  "awk '/^## Open decisions/,/^## [^O]/' '$CANON' | grep >/dev/null 'owner conversation'"
check "states it is not required for direct or scoped plans" \
  "awk '/^## Open decisions/,/^## [^O]/' '$CANON' | grep >/dev/null -i 'direct'"
check "the plan template carries the section as optional" \
  "grep -q '^## Open decisions .*optional' '$CANON'"

# --- validator: a plan with the section and one without it both validate -------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

write_plan() {  # $1=path  $2=1 to include the Open decisions section
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'EOF'
---
title: "Fixture plan"
status: open
created: 2026-09-21
updated: 2026-09-21
current-phase: 0
---

# Fixture Plan

**Goal:** Exercise the validator.

**Design concept:** A plan that exists only for this test.

**Non-goals:**
- Anything real
EOF
  if [[ "$2" == "1" ]]; then
    cat >> "$1" <<'EOF'

## Open decisions

- Which cache key the resolver uses — unblocker: prototype
- Whether the export stays synchronous — unblocker: owner conversation
EOF
  fi
  cat >> "$1" <<'EOF'

## Phase 1: Do the thing  (tier: standard, phase-type: afk-impl, tests: unit)

**Goal:** Deliver the thing.

**Acceptance:**
- `bash tests/run-all.sh` exits 0

**Verify:**

```bash
bash tests/run-all.sh
```

## Phase 1 Checkpoint

**Completed:**
- [ ] Task 1.1: the work

## Session Checkpoint

**Status:** open
**Phase:** 1
**Next:** Task 1.1
EOF
}

violations_for() {  # $1=with|without -> prints the violation count
  local ctx="$TMP/$1/.context"
  mkdir -p "$ctx/plans/_archive"
  local flag=0; [[ "$1" == "with" ]] && flag=1
  write_plan "$ctx/plans/2026-09-21-fixture.md" "$flag"
  python3 "$VALIDATE" "$ctx" --type plans --json 2>/dev/null \
    | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["violations"]))'
}

echo "validate.py --type plans:"
WITH="$(violations_for with)"
WITHOUT="$(violations_for without)"
check "a plan WITH the section has 0 violations (got ${WITH:-?})" "[[ '$WITH' == 0 ]]"
check "a plan WITHOUT the section has 0 violations (got ${WITHOUT:-?})" "[[ '$WITHOUT' == 0 ]]"

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
