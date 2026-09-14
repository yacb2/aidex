#!/usr/bin/env bash
# test-inventory-duplicate-id.sh — a finding id that appears twice in
# 00-inventory.md is refused by validate-audit.sh (audit-duplicate-id) AND by
# reindex-audits.sh, which must not regenerate 00-index.md over it (BL-389:
# USAGE-19..23 were issued once per run and every append-note was ambiguous).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
REINDEX="$SCRIPT_DIR/reindex-audits.sh"
VALIDATE="$SCRIPT_DIR/validate-audit.sh"

pass=0; fail=0
check() { if eval "$2"; then echo "  ok: $1"; pass=$((pass+1)); else echo "  FAIL: $1"; fail=$((fail+1)); fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
mkdir -p .context/audits/20260601-foo .context/audits/20260901-bar
for r in foo bar; do d=$(ls -d .context/audits/*-$r); cat > "$d/index.md" <<EOR
---
title: "$r audit"
status: doing
created: 2026-06-01
updated: 2026-06-01
methodology: usage-retro
---
# $r
EOR
done

inventory() {   # $1 = id of the second run's row
cat > .context/audits/00-inventory.md <<EOR
# Inventory

| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| USAGE-19 | gap | dash | first run's claim | open | P2 | 20260601-foo | — | n |
| $1 | gap | audit | second run's claim | open | P2 | 20260901-bar | — | n |
EOR
}

echo "== duplicate id =="
inventory USAGE-19
out="$(bash "$VALIDATE" .context/audits 2>&1)"; rc=$?
check "validate-audit.sh exits 1 on a duplicate id" '[[ $rc -eq 1 ]]'
check "…and names it as audit-duplicate-id" '[[ "$out" == *audit-duplicate-id* && "$out" == *USAGE-19* ]]'
out="$(bash "$REINDEX" 2>&1)"; rc=$?
check "reindex-audits.sh refuses to regenerate" '[[ $rc -ne 0 ]]'
check "…names the duplicate id" '[[ "$out" == *USAGE-19* ]]'
check "…and writes no 00-index.md" '[[ ! -f .context/audits/00-index.md ]]'

echo "== renumbered =="
inventory USAGE-20
check "validate-audit.sh reports no duplicate once renumbered" '! bash "$VALIDATE" .context/audits 2>&1 | grep -q audit-duplicate-id'
check "reindex-audits.sh regenerates" 'bash "$REINDEX" >/dev/null 2>&1 && [[ -f .context/audits/00-index.md ]]'
check "…counting one finding per run" 'grep -q "1 open / 1 findings" .context/audits/00-index.md'

echo "passed=$pass failed=$fail"
[[ $fail -eq 0 ]]
