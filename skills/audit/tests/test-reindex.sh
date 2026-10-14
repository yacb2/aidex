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
close_out="$(bash "$CLOSE" 20260601-foo --force 2>&1)"
check "run archived"              '[[ -d .context/audits/_archive/20260601-foo ]]'
# The reported destination must be the one that exists. It used to be assembled as
# `$(dirname "$DEST")/_archive/`, where dirname is ALREADY <parent>/_archive, so the
# success line named a doubled path nobody could open.
# Scoped to the "Archived audit run" LINE. close-audit.sh also prints $DEST on its
# own line, so a grep over the whole output is satisfied by that one and passes even
# when the message is wrong — verified by mutation. An assertion about a message has
# to read that message.
check "the archived-run message names a path that exists" \
  'line="$(grep "Archived audit run" <<<"$close_out")"; dest="$(grep -oE "/[^ ]*20260601-foo" <<<"$line" | sed -n 1p)"; [[ -n "$dest" && -d "$dest" ]]'
check "no doubled _archive in the message" '[[ "$close_out" != *"_archive/_archive"* ]]'
check "now under Archived runs"   'sed -n "/## Archived runs/,\$p" "$IDX" | grep >/dev/null "Foo audit"'
check "gone from Active"          '! sed -n "/## Active runs/,/^---/p" "$IDX" | grep >/dev/null "(20260601-foo/index.md)"'
check "counts survive archive"    'grep -q "1 open / 2 findings" "$IDX"'

echo "== --check drift detection =="
bash "$REINDEX" >/dev/null 2>&1
check "--check passes when fresh" 'bash "$REINDEX" --check >/dev/null 2>&1'
mkdir -p .context/audits/20260701-bar
printf -- '---\ntitle: "Bar"\nstatus: doing\ncreated: 2026-07-01\nmethodology: ux-audit\n---\n' > .context/audits/20260701-bar/index.md
check "--check fails when stale"  '! bash "$REINDEX" --check >/dev/null 2>&1'

echo "== a row with an inline HTML comment is still counted (audit-s29) =="
mkdir -p "$TMP/inline" && cd "$TMP/inline"
mkdir -p .context/audits/20260801-inl
printf -- '---\ntitle: "Inl"\nstatus: doing\ncreated: 2026-08-01\nmethodology: ux-audit\n---\n' > .context/audits/20260801-inl/index.md
cat > .context/audits/00-inventory.md <<'EOF'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| UX-09-1 | bug | auth | commented <!-- todo --> row | open | P1 | 20260801-inl | — | n |
EOF
bash "$REINDEX" >/dev/null 2>&1
check "inline-comment row counted" 'grep -q "1 open / 1 findings" .context/audits/00-index.md'
# audit-s29 (round 2): a multi-line comment block still hides its example row
mkdir -p "$TMP/inline2" && cd "$TMP/inline2"
mkdir -p .context/audits/20260801-inl
printf -- '---\ntitle: "Inl"\nstatus: doing\ncreated: 2026-08-01\nmethodology: ux-audit\n---\n' > .context/audits/20260801-inl/index.md
cat > .context/audits/00-inventory.md <<'EOF'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
<!--
| UX-09-8 | bug | auth | example | open | P1 | 20260801-inl | — | n |
-->
| UX-09-1 | bug | auth | commented <!-- todo --> row | open | P1 | 20260801-inl | — | n |
EOF
bash "$REINDEX" >/dev/null 2>&1
check "multi-line comment example row not counted" 'grep -q "1 open / 1 findings" .context/audits/00-index.md'
# audit-s29 (round 2): the duplicate-id scan sees a row that carries an inline comment
cat > .context/audits/00-inventory.md <<'EOF'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| UX-09-1 | bug | auth | first | open | P1 | 20260801-inl | — | n |
| UX-09-1 | bug | auth | second <!-- dup --> | open | P1 | 20260801-inl | — | n |
EOF
dup_out="$(bash "$REINDEX" 2>&1)"; dup_rc=$?
check "dup scan refuses an inline-commented duplicate" '[[ $dup_rc -eq 2 && "$dup_out" == *"duplicate finding id"* ]]'
cd "$TMP/inline"
# audit-s42: close-audit still closes when the reindex fails, and says so
printf '%s\n%s\n' '| UX-09-2 | bug | auth | dup | open | P1 | 20260801-inl | — | n |' '| UX-09-2 | bug | auth | dup | open | P1 | 20260801-inl | — | n |' >> .context/audits/00-inventory.md
close42="$(bash "$CLOSE" 20260801-inl --force 2>&1)"; rc42=$?
check "close-audit survives a failing reindex" '[[ $rc42 -eq 0 && -d .context/audits/_archive/20260801-inl ]]'
check "close-audit reports the failing reindex" '[[ "$close42" == *"index not regenerated"*"duplicate finding id"* ]]'

echo ""
echo "reindex-audits: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
