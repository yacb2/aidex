#!/usr/bin/env bash
# test-profile-init.sh — profile-init.py reads FACTS from disk and never invents one.
#
# Fixture: a minimal project with the three files the script reads. A key the files
# do not answer must come out blank (not a guessed default), the script must refuse
# to overwrite without --force, and the single-test command forms must carry {path}
# / {spec} so a caller can substitute instead of composing.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT="$HERE/../scripts/profile-init.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

mkdir -p "$TMP/p/backend" "$TMP/p/frontend/tests/e2e/helpers"
cat > "$TMP/p/test-e2e.sh" <<'SH'
#!/bin/bash
DB_PORT=${DB_PORT:-5600}
DB_USER=demo_user
DB_TEMPLATE=demo_app_e2e_template
DB_E2E=demo_app_e2e
E2E_FE_PORT="${E2E_FRONTEND_PORT:-3610}"
export DB_PASSWORD=x
docker compose run --rm backend-test python manage.py bootstrap_e2e_data
SH
cat > "$TMP/p/docker-compose.yml" <<'YML'
services:
  backend:
    ports:
      - "${BACKEND_PORT:-8600}:8600"
  backend-test:
    ports:
      - "${E2E_BACKEND_PORT:-8610}:8600"
    profiles: [e2e]
YML
printf '[tool.pytest.ini_options]\n' > "$TMP/p/backend/pyproject.toml"
printf '{"dependencies":{"vue":"^3"},"devDependencies":{"vitest":"^4","reka-ui":"^2","@playwright/test":"^1"}}\n' > "$TMP/p/frontend/package.json"
printf 'export default { server: { port: 3600 } }\n' > "$TMP/p/frontend/vite.config.ts"

out="$(python3 "$SCRIPT" "$TMP/p")"
[[ "$out" == *"wrote $TMP/p/.context/testing-profile.md"* ]] || fail "did not report the written path: $out"
prof="$TMP/p/.context/testing-profile.md"
for kv in "project_slug: demo_app" "project_kebab: demo-app" "db_port: 5600" "db_user: demo_user" \
          "dev_frontend_port: 3600" "dev_backend_port: 8600" "e2e_frontend_port: 3610" "e2e_backend_port: 8610" \
          "e2e_service: backend-test" "seed_e2e_bootstrap_cmd: bootstrap_e2e_data" \
          "backend_test_cmd: docker compose exec backend pytest {path}" "e2e_test_cmd: ./test-e2e.sh {spec}" \
          "helpers_dir: frontend/tests/e2e/helpers" "ui_stack: reka-ui" \
          "testing_packs: testing-django testing-vue testing-playwright-app"; do
  grep -qxF "$kv" "$prof" || fail "missing '$kv' in profile:
$(cat "$prof")"
done
# Unanswered keys stay blank — the script does not guess a locale or a seed command.
grep -qx "ui_locale: " "$prof" || fail "ui_locale must be blank when nothing on disk answers it"
grep -qx "seed_bootstrap_cmd: " "$prof" || fail "seed_bootstrap_cmd must be blank: fixture never calls bootstrap_data"
[[ "$out" == *"blank: "*"ui_locale"* ]] || fail "blank keys must be named in the report: $out"
# Refuses to overwrite silently.
if python3 "$SCRIPT" "$TMP/p" >/dev/null 2>&1; then fail "second run must refuse without --force"; fi
python3 "$SCRIPT" --force "$TMP/p" >/dev/null || fail "--force must overwrite"
# --print never writes.
rm "$prof"; python3 "$SCRIPT" --print "$TMP/p" | grep -q "^project_slug: demo_app$" || fail "--print output"
[[ -e "$prof" ]] && fail "--print must not write"
# A web project (no backend/, root package.json) resolves the web packs, never the app ones.
mkdir -p "$TMP/w"
printf '{"dependencies":{"payload":"^3","svelte":"^5"},"devDependencies":{"vitest":"^4","@playwright/test":"^1"}}\n' > "$TMP/w/package.json"
python3 "$SCRIPT" --print "$TMP/w" | grep -qx "testing_packs: testing-payload testing-svelte testing-playwright-web" \
  || fail "web fixture packs: $(python3 "$SCRIPT" --print "$TMP/w" | grep testing_packs)"
echo "OK — profile-init: facts read, blanks stay blank, overwrite refused, --print is read-only"
