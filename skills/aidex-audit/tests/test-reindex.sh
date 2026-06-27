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

| ID | Type | Module | Summary | Status | Severity | First Seen | Last Updated | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| UX-01-1 | bug | auth | open one | open | P1 | 2026-06-01 | 2026-06-01 | 20260601-foo | — | n |
| UX-01-2 | gap | auth | done one | done | P2 | 2026-06-01 | 2026-06-01 | 20260601-foo | — | n |
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

echo "== reindex =="
bash "$REINDEX" >/dev/null 2>&1
IDX=.context/audits/00-index.md
check "index created"             '[[ -f "$IDX" ]]'
check "Active runs has foo"       'grep -q "## Active runs" "$IDX" && grep -q "Foo audit" "$IDX"'
check "shows methodology+status"  'grep -q "ux-audit · doing" "$IDX"'
check "derives 1 open / 2 counts" 'grep -q "1 open / 2 findings" "$IDX"'
check "runs counts: 1 active 0 archived" 'grep -q "\*\*Runs:\*\* 1 active · 0 archived" "$IDX"'

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
