#!/usr/bin/env bash
# test-reindex.sh — reindex-plans.sh builds plans/00-index.md from front-matter,
# and close-plan.sh regenerates it (active → Closed) on close.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
REINDEX="$SCRIPT_DIR/reindex-plans.sh"
CLOSE="$SCRIPT_DIR/close-plan.sh"

pass=0; fail=0
check() { if eval "$2"; then echo "  ok: $1"; pass=$((pass+1)); else echo "  FAIL: $1"; fail=$((fail+1)); fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
mkdir -p .context/plans/_archive

# single-file plan (open, no current-phase — exercises the empty-middle-field case)
cat > .context/plans/2026-06-01-single.md <<'EOF'
---
title: "Single file plan"
status: open
created: 2026-06-01
updated: 2026-06-02
---
# Single file plan
EOF

# modular plan (doing, current-phase 2, two phase files)
mkdir -p .context/plans/2026-06-03-modular
cat > .context/plans/2026-06-03-modular/00-index.md <<'EOF'
---
title: "Modular plan"
status: doing
current-phase: 2
created: 2026-06-03
updated: 2026-06-04
---
# Modular plan
EOF
: > .context/plans/2026-06-03-modular/01-a.md
: > .context/plans/2026-06-03-modular/02-b.md

# already-archived plan (done)
cat > .context/plans/_archive/2026-05-20-old.md <<'EOF'
---
title: "Old done plan"
status: done
created: 2026-05-20
updated: 2026-05-21
---
# Old done plan
EOF

# done plan still in the active dir (not yet archived) — must NOT vanish
cat > .context/plans/2026-05-25-stranded.md <<'EOF'
---
title: "Stranded done plan"
status: done
created: 2026-05-25
updated: 2026-05-26
---
# Stranded done plan
EOF

echo "== reindex =="
bash "$REINDEX" >/dev/null 2>&1
IDX=.context/plans/00-index.md
check "index created"               '[[ -f "$IDX" ]]'
check "Open section has single"     'grep -q "## Open" "$IDX" && grep -q "Single file plan" "$IDX"'
check "Doing section has modular"   'grep -q "## Doing" "$IDX" && grep -q "Modular plan" "$IDX"'
check "modular shows phase 2/2"     'grep -q "phase 2/2" "$IDX"'
check "single not misparsed"        'grep -q "Single file plan.*open · updated 2026-06-02" "$IDX"'
check "Closed has archived plan"    'grep -q "## Closed" "$IDX" && grep -q "Old done plan" "$IDX"'
check "done-in-active not vanished"  'grep -q "Stranded done plan" "$IDX" && grep -q "Stranded done plan.*not archived" "$IDX"'
check "stranded not in Open/Doing"   '! sed -n "/## Open/,/^---/p" "$IDX" | grep -q "Stranded"'
check "active counts: Open 1 Doing 1" 'grep -q "\*\*Open:\*\* 1 · \*\*Doing:\*\* 1" "$IDX"'

echo "== close-plan regenerates =="
bash "$CLOSE" 2026-06-01-single >/dev/null 2>&1
check "single archived"             '[[ -f .context/plans/_archive/2026-06-01-single.md ]]'
check "single now in Closed"        'grep -q "Single file plan" "$IDX" && sed -n "/## Closed/,\$p" "$IDX" | grep -q "Single file plan"'
check "single gone from Open"       '! grep -q "(2026-06-01-single.md)" <(sed -n "/## Open/,/^---/p" "$IDX")'

echo "== --check drift detection =="
bash "$REINDEX" >/dev/null 2>&1
check "--check passes when fresh" 'bash "$REINDEX" --check >/dev/null 2>&1'
sed -i.bak 's/status: doing/status: done/' .context/plans/2026-06-03-modular/00-index.md
check "--check fails when stale"  '! bash "$REINDEX" --check >/dev/null 2>&1'

echo ""
echo "reindex-plans: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
