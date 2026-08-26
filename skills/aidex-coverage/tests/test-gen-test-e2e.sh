#!/usr/bin/env bash
# test-gen-test-e2e.sh — the generator reads the profile, refuses blanks by name, leaves
# no placeholder behind, and the script it writes honours aidex-worktree's precondition
# (sources the worktree .env before the port defaults apply; exports E2E_DB_PORT).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GEN="$HERE/../scripts/gen-test-e2e.sh"; INIT="$HERE/../scripts/profile-init.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
mkdir -p "$TMP/p/.context"
if "$GEN" "$TMP/p" >/dev/null 2>&1; then fail "missing profile must exit 2"; fi
python3 "$INIT" "$TMP/p" >/dev/null   # nothing on disk: every key blank
err="$("$GEN" "$TMP/p" 2>&1 >/dev/null || true)"
[[ "$err" == *project_slug* && "$err" == *db_port* ]] || fail "blank keys must be named: $err"
cat > "$TMP/p/.context/testing-profile.md" <<'P'
---
project_slug: demo_app
project_kebab: demo-app
dev_frontend_port: 3600
dev_backend_port: 8600
db_port: 5600
e2e_frontend_port: 3610
e2e_backend_port: 8610
db_name: demo_app
db_user: demo_user
db_password_env: DB_PASSWORD
e2e_service: backend-test
seed_bootstrap_cmd: bootstrap_data
seed_e2e_bootstrap_cmd: bootstrap_e2e_data
---
P
"$GEN" "$TMP/p" >/dev/null || fail "generation with a filled profile"
S="$TMP/p/test-e2e.sh"
[[ -x "$S" ]] || fail "output must be executable"
grep -q '{{' "$S" && fail "placeholder left behind: $(grep -n '{{' "$S" | head -3)"
bash -n "$S" || fail "generated script does not parse"
grep -q 'demo_app_e2e_template' "$S" || fail "template DB name not derived from project_slug"
grep -qE 'playwright test --config=playwright\.e2e\.config\.ts "\$@"' "$S" || fail "must forward \"\$@\" to the isolated config"
grep -q 'COMPOSE_PROJECT_NAME=' "$S" && fail "must not set COMPOSE_PROJECT_NAME"
src_line="$(grep -n 'PROJECT_ROOT/.env' "$S" | head -1 | cut -d: -f1)"
def_line="$(grep -n 'DB_PORT:-' "$S" | head -1 | cut -d: -f1)"
[[ -n "$src_line" && -n "$def_line" && "$src_line" -lt "$def_line" ]] || fail ".env must be sourced before the DB_PORT default ($src_line vs $def_line)"
grep -q 'export E2E_DB_PORT' "$S" || fail "E2E_DB_PORT must be exported"
if "$GEN" "$TMP/p" >/dev/null 2>&1; then fail "second run must refuse without --force"; fi
"$GEN" --force "$TMP/p" >/dev/null || fail "--force"
"$S" --help | head -3 | grep -q 'spec' || fail "usage must show the single-spec form first"
echo "OK — gen-test-e2e: profile-driven, blanks named, no placeholders, .env before defaults, single-spec usage"
