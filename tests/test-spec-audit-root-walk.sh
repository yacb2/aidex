#!/usr/bin/env bash
# test-spec-audit-complete.sh must find `.context/` at the PROJECT root, which since the
# workspace split (BL-412) is the parent of the public repo, not the repo itself.
# Fixture: ws/.context/references/coverage/<table> + ws/repo/tests/<the test> + a fake
# EchoLab timeline. PASS with the table at the workspace level; FAIL when no .context/
# is reachable (the mutation), never a silent PASS.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ws/repo/tests" "$T/ws/repo/skills/conventions/scripts" "$T/ws/.context/references/coverage" \
         "$T/echo/frontend/tests/e2e/timeline"
cp "$HERE/test-spec-audit-complete.sh" "$T/ws/repo/tests/"
cp "$HERE/../skills/conventions/scripts/_lib.sh" "$T/ws/repo/skills/conventions/scripts/"
touch "$T/echo/frontend/tests/e2e/timeline/a.spec.ts"
printf '| spec | layer |\n|---|---|\n| `a.spec.ts` | e2e |\n' > "$T/ws/.context/references/coverage/01-echolab-e2e-layer-audit.md"
git -C "$T/ws/repo" init -q
out="$(cd "$T/ws/repo" && ECHOLAB_PATH="$T/echo" bash tests/test-spec-audit-complete.sh 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q "^PASS" <<<"$out" || { echo "FAIL: table at the workspace root not found (rc=$rc)"; echo "$out" | tail -3; exit 1; }
rm -rf "$T/ws/.context"
out="$(cd "$T/ws/repo" && ECHOLAB_PATH="$T/echo" bash tests/test-spec-audit-complete.sh 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: without any .context/ the gate must fail loudly, got rc=$rc"; exit 1; }
echo "OK — spec-audit resolves .context/ at the project root above the repo; no .context/ anywhere fails"
