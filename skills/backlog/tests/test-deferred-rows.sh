#!/usr/bin/env bash
# test-deferred-rows.sh — the index's Deferred section (BL-828).
#
# Layer: shell integration in an isolated temp project; the index is a pure function of the
# tree, so the rendered rows are the boundary. Pins: newest `updated` first, an item with no
# `updated` sorts last as 0000-00-00 (and prints no date), ties break on the rendered line
# descending, blocked_by always renders (empty too), ready_when only when set, no id and no
# title degrade to the plain row. Golden coverage in test-index-identical.sh is one fixture;
# this owns the ordering and the field rendering.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
D="$TMP/p/.context/backlog/_deferred"; mkdir -p "$D"; cd "$TMP/p"
# mk <file> <title> <id> <updated> <blocked_by> <ready_when>; an empty argument omits the field
mk() {
  { printf -- '---\n'
    [[ -n "$2" ]] && printf 'title: "%s"\n' "$2"
    [[ -n "$3" ]] && printf 'id: %s\n' "$3"
    printf 'status: open\npriority: P1\n'
    [[ -n "$4" ]] && printf 'updated: %s\n' "$4"
    printf 'blocked_by: "%s"\n' "$5"
    [[ -n "$6" ]] && printf 'ready_when: "%s"\n' "$6"
    printf -- '---\n\n# x\n'; } > "$D/$1.md"
}
mk 2026-01-01-a-old   "Old"      BL-001 2026-01-01 "waiting on A" ""
mk 2026-03-01-b-new   "Newest"   BL-002 2026-03-01 "owner answer" "date:2026-12-01"
mk 2026-02-01-c-undated "Undated" BL-003 ""          "no date"      ""
mk 2026-02-02-d-tie-a "Tie A"    BL-004 2026-02-02 "t" ""
mk 2026-02-02-e-tie-b "Tie B"    BL-005 2026-02-02 "t" ""
mk 2026-02-03-f-notitle ""       ""     2026-02-03 ""             ""
bash "$SCRIPTS/register-item.sh" --reindex >/dev/null 2>&1
rows="$(sed -n '/^## Deferred/,/^---/p' .context/backlog/00-index.md | grep '^- ')"

expected="$(cat <<'X'
- **BL-002** · [Newest](_deferred/2026-03-01-b-new.md) — P1 · blocked_by: "owner answer" · ready_when: "date:2026-12-01" · 2026-03-01
- [(untitled)](_deferred/2026-02-03-f-notitle.md) — P1 · blocked_by: "" · 2026-02-03
- **BL-005** · [Tie B](_deferred/2026-02-02-e-tie-b.md) — P1 · blocked_by: "t" · 2026-02-02
- **BL-004** · [Tie A](_deferred/2026-02-02-d-tie-a.md) — P1 · blocked_by: "t" · 2026-02-02
- **BL-001** · [Old](_deferred/2026-01-01-a-old.md) — P1 · blocked_by: "waiting on A" · 2026-01-01
- **BL-003** · [Undated](_deferred/2026-02-01-c-undated.md) — P1 · blocked_by: "no date"
X
)"
if [[ "$rows" == "$expected" ]]; then ok "deferred rows: order, undated last without a date, blocked_by/ready_when rendering"
else bad "deferred rows differ"; diff <(printf '%s\n' "$expected") <(printf '%s\n' "$rows") >&2; fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"; [[ $FAIL -eq 0 ]]
