#!/usr/bin/env bash
# test-reindex.sh — reindex-audits.sh builds audits/00-index.md as a run-level
# roll-up, deriving per-run finding counts from 00-inventory.md, and close-audit.sh
# regenerates it (Active → Archived) on close.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
REINDEX="$SCRIPT_DIR/reindex-audits.sh"
CLOSE="$SCRIPT_DIR/close-audit.sh"

pass=0; fail=0
check() { if eval "$2"; then echo "  ok: $1"; pass=$((pass+1)); else echo "  FAIL: $1"; fail=$((fail+1)); fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
mkdir -p .context/audits/20260601-foo

# Inventory: 2 findings for run foo — one open, one done → 1 open / 2 total.
cat > .context/audits/00-inventory.md <<'EOF'
# Inventory

| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| UX-01-1 | bug | auth | open one | open | P1 | 20260601-foo | — | n |
| UX-01-2 | gap | auth | done one | done | P2 | 20260601-foo | — | n |
EOF

cat > .context/audits/20260601-foo/index.md <<'EOF'
---
title: "Foo audit"
status: doing
created: 2026-06-01
updated: 2026-06-01
methodology: ux-audit
---
# Foo audit
EOF

# run that uses 00-index.md (not index.md) as its run header — must be recognized
mkdir -p .context/audits/20260602-bar
cat > .context/audits/20260602-bar/00-index.md <<'EOF'
---
title: "Bar audit"
status: done
created: 2026-06-02
methodology: perf-audit
---
# Bar audit
EOF

# nested per-methodology layout: audits/security/<run>/index.md + its own inventory
mkdir -p .context/audits/security/20260603-sec
cat > .context/audits/security/20260603-sec/index.md <<'EOF'
---
title: "Sec audit"
status: doing
created: 2026-06-03
---
# Sec audit
EOF
cat > .context/audits/security/00-inventory.md <<'EOF'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| SEC-1 | bug | api | x | open | P0 | 20260603-sec | — | n |
EOF

# ad-hoc audit dir with findings but no run index — must surface as unrecognized
mkdir -p .context/audits/adhoc-recorrido
printf '# Findings\n- a bug\n' > .context/audits/adhoc-recorrido/FINDINGS.md

# asset-only dir (no .md) — must be skipped silently
mkdir -p .context/audits/_shots && printf 'x' > .context/audits/_shots/a.png

echo "== reindex =="
bash "$REINDEX" >/dev/null 2>&1
IDX=.context/audits/00-index.md
check "index created"             '[[ -f "$IDX" ]]'
check "Active runs has foo"       'grep -q "## Active runs" "$IDX" && grep -q "Foo audit" "$IDX"'
check "shows methodology+status"  'grep -q "ux-audit · doing" "$IDX"'
check "derives 1 open / 2 counts" 'grep -q "1 open / 2 findings" "$IDX"'
check "00-index.md run recognized" 'grep -q "Bar audit" "$IDX" && grep -q "20260602-bar/00-index.md" "$IDX"'
check "nested run recognized"     'grep -q "Sec audit" "$IDX" && grep -q "security/20260603-sec/index.md" "$IDX"'
check "nested uses own inventory" 'grep -q "Sec audit.*1 open / 1 findings" "$IDX"'
check "ad-hoc dir surfaced"       'grep -q "## Unrecognized run folders" "$IDX" && grep -q "adhoc-recorrido" "$IDX"'
check "asset dir skipped"         '! grep -q "_shots" "$IDX"'

echo "== close-audit regenerates =="
bash "$CLOSE" 20260601-foo --force >/dev/null 2>&1
check "run archived"              '[[ -d .context/audits/_archive/20260601-foo ]]'
check "now under Archived runs"   'sed -n "/## Archived runs/,\$p" "$IDX" | grep -q "Foo audit"'
check "gone from Active"          '! sed -n "/## Active runs/,/^---/p" "$IDX" | grep -q "(20260601-foo/index.md)"'
check "counts survive archive"    'grep -q "1 open / 2 findings" "$IDX"'

echo "== --check drift detection =="
bash "$REINDEX" >/dev/null 2>&1
check "--check passes when fresh" 'bash "$REINDEX" --check >/dev/null 2>&1'
mkdir -p .context/audits/20260701-bar
printf -- '---\ntitle: "Bar"\nstatus: doing\ncreated: 2026-07-01\nmethodology: ux-audit\n---\n' > .context/audits/20260701-bar/index.md
check "--check fails when stale"  '! bash "$REINDEX" --check >/dev/null 2>&1'

echo ""
echo "reindex-audits: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
