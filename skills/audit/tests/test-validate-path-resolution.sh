#!/usr/bin/env bash
# test-validate-path-resolution.sh — validate-audit.sh [path] validates the project
# the PATH names, whatever the path points at inside it and wherever it is run from.
#
#   1. A run folder under a methodology (audits/<m>/<run>) climbs to the audits
#      root: the usage line documents a "run/methodology sub-folder", and only the
#      methodology folder used to climb, so a run folder was validated as the root
#      (0 methodologies, rc 0, every violation missed).
#      A relative path climbs too (it is made absolute first), and a directory
#      with no `audits` ancestor is validated as given — the climb stops at /.
#   2. The index-freshness check reads the target project's 00-index.md, not the
#      one of the cwd: run from outside the project, a stale index is still named.
#
# Layer: script CLI — both are decisions about which directory the script reads.
set -uo pipefail

VALIDATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)/validate-audit.sh"
REINDEX="$(dirname "$VALIDATE")/reindex-audits.sh"

pass=0; fail=0
check() { if eval "$2"; then echo "  ok: $1"; pass=$((pass+1)); else echo "  FAIL: $1"; fail=$((fail+1)); fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/elsewhere"

echo "== run folder as the path =="
A="$TMP/p1/.context/audits"
mkdir -p "$A/ux/2026-10-01-login"
printf '# ux\n' > "$A/ux/00-methodology.md"
printf '# ux\n' > "$A/ux/00-changelog.md"
cat > "$A/ux/00-inventory.md" <<'EOF'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| UX-1 | gap | core | done with no evidence | done | P2 | 2026-10-01-login | — | — |
EOF
printf -- '---\ntitle: "login"\nstatus: done\ncreated: 2026-10-01\nupdated: 2026-10-01\n---\n' > "$A/ux/2026-10-01-login/index.md"
printf '# Findings\n\n### UX-1\n' > "$A/ux/2026-10-01-login/findings.md"
out="$(cd "$TMP/p1" && bash "$VALIDATE" --json "$A/ux/2026-10-01-login" 2>&1)"; rc=$?
check "validates the audits root, not the run folder" '[[ "$out" == *"\"audits_dir\": \"$A\""* && "$out" == *"\"methodologies\": 1"* ]]'
check "…and reports the methodology violation (rc 1)" '[[ $rc -eq 1 && "$out" == *audit-lifecycle-done-unevidenced* ]]'

echo "== relative methodology folder, from inside audits/ =="
# Bounded too: a relative path that is not made absolute climbs to "." and stays.
out="$(cd "$A" && perl -e 'alarm 10; exec @ARGV' bash "$VALIDATE" --json ux 2>&1)"
check "climbs from a relative 'ux' to the audits root" '[[ "$out" == *"\"audits_dir\": \"$A\""* && "$out" == *"\"methodologies\": 1"* ]]'

echo "== a directory with no audits ancestor =="
# Bounded: a climb that never stops at / would hang here, not fail.
mkdir -p "$TMP/n/o/plain"
out="$(cd "$TMP/elsewhere" && perl -e 'alarm 10; exec @ARGV' bash "$VALIDATE" --json "$TMP/n/o/plain" 2>&1)"; rc=$?
check "returns, validating the directory as given" '[[ $rc -eq 0 && "$out" == *"\"audits_dir\": \"$TMP/n/o/plain\""* ]]'

echo "== index freshness, run from outside the project =="
B="$TMP/p2/.context/audits"
for r in 2026-10-01-one 2026-10-02-two; do
  mkdir -p "$B/$r"
  printf -- '---\ntitle: "%s"\nstatus: doing\ncreated: 2026-10-01\nupdated: 2026-10-01\n---\n' "$r" > "$B/$r/index.md"
done
(cd "$TMP/p2" && bash "$REINDEX" >/dev/null 2>&1)
mkdir -p "$B/2026-10-03-three"
printf -- '---\ntitle: "three"\nstatus: doing\ncreated: 2026-10-03\nupdated: 2026-10-03\n---\n' > "$B/2026-10-03-three/index.md"
out="$(cd "$TMP/elsewhere" && bash "$VALIDATE" "$B" 2>&1)"
check "names the target's stale 00-index.md from an unrelated cwd" '[[ "$out" == *audit-index-stale* ]]'

echo "passed=$pass failed=$fail"
[[ $fail -eq 0 ]]
