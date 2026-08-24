#!/usr/bin/env bash
# Archiving a standalone run must not turn its backlog references into orphans.
#
# The orphan check already knows a standalone run has no board to check against:
# `audit/<run>/<id>` is 3 segments and is skipped on purpose. But D-10 archives a
# finished run into `_archive/`, and `--escalate` then writes
# `audit/_archive/<run>/<id>` — 4 segments, because `_archive` occupies one. The
# 4-segment branch is the `<methodology>/<run>/<id>` branch, so `_archive` is read
# as a methodology name and every reference is reported as an orphan.
#
# Observed 2026-08-24: escalating 14 findings out of the archived 3mo-retro run
# produced 14 violations at once, none of them real. Same shape as f405d8d, where
# validate.py did not resolve refs into `_archive/` either — archiving is what D-10
# mandates, so a checker that punishes it is checking the wrong thing.
#
# Invariants:
#   1. `audit/<run>/<id>` (standalone, live) raises nothing.
#   2. `audit/_archive/<run>/<id>` (standalone, archived) raises nothing.
#   3. `audit/<methodology>/<run>/<id>` with an id on no board still violates.
#   4. `audit/_archive/<methodology>/<run>/<id>` with an id on no board still violates
#      — stripping `_archive` must not cost the check its teeth.
#
# Run: bash skills/aidex-audit/tests/test-archived-run-origin-ref.sh
set -euo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATE="$SKILL/scripts/validate-audit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

CTX="$TMP/.context"
AUD="$CTX/audits"
M="$AUD/probe"
mkdir -p "$M/2026-01-01-probe" "$AUD/_archive/2026-01-01-solo" "$CTX/backlog"

cat > "$M/00-inventory.md" <<'INV'
# probe Inventory

| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| PR-01 | bug | core | A real finding that is on the board | open | P2 | 2026-01-01-probe | — | — |
INV
printf '# probe methodology\n' > "$M/00-methodology.md"
printf '# probe changelog\n'   > "$M/00-changelog.md"
printf -- '---\ntitle: "probe"\nstatus: done\ncreated: 2026-01-01\nupdated: 2026-01-01\n---\n\n# probe\n' > "$M/2026-01-01-probe/index.md"
printf -- '---\ntitle: "solo"\nstatus: done\ncreated: 2026-01-01\nupdated: 2026-01-01\n---\n\n# solo\n' > "$AUD/_archive/2026-01-01-solo/index.md"

bl() { # $1 = filename stem, $2 = origin_ref
  printf -- '---\ntitle: "probe item"\nstatus: open\ncreated: 2026-01-01\nupdated: 2026-01-01\norigin_ref: "%s"\n---\n\n# probe item\n' \
    "$2" > "$CTX/backlog/2026-01-01-bl-001-$1.md"
}
cited() { grep -o 'cites audit finding [A-Z0-9-]*' "$TMP/out" 2>/dev/null | awk '{print $4}' | sort -u | tr '\n' ' ' || true; }
run() { "$VALIDATE" "$AUD" >"$TMP/out" 2>&1 || true; rm -f "$CTX/backlog"/2026-01-01-bl-001-*.md; }

# ---- 1: standalone, live ----
bl live "audit/2026-01-01-solo/SOLO-01"; run
got="$(cited)"; [[ -z "$got" ]] || err "(1) a live standalone run has no board to check; got: $got"

# ---- 2: standalone, archived — the RED case ----
bl arch "audit/_archive/2026-01-01-solo/SOLO-01"; run
got="$(cited)"; [[ -z "$got" ]] || err "(2) archiving a standalone run must not orphan its refs; got: $got"

# ---- 3: methodology run, id on no board — teeth ----
bl teeth "audit/probe/2026-01-01-probe/PR-99"; run
got="$(cited)"; [[ "$got" == *"PR-99"* ]] || err "(3) an id on no board must still violate; got: '$got'"

# ---- 4: archived methodology run, id on no board — teeth survive the strip ----
bl teeth2 "audit/_archive/probe/2026-01-01-probe/PR-98"; run
got="$(cited)"; [[ "$got" == *"PR-98"* ]] || err "(4) stripping _archive must not cost the check its teeth; got: '$got'"

if [[ $fail -eq 0 ]]; then echo "OK: an archived standalone run's refs are not orphans; the teeth survive"; fi
exit $fail
