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
# --check (BL-271): the profile stays facts-only and no testing module crosses the
# tripwire. NS's profile grew to 553 words with prose sections, and its
# 06-cross-dependencies.md to 4,282 words holding four workflows, because nothing
# said either shape was wrong.
python3 "$SCRIPT" --force "$TMP/p" >/dev/null
mkdir -p "$TMP/p/.context/references/testing"
printf '# Small\n\none workflow, under the tripwire.\n' > "$TMP/p/.context/references/testing/01-small.md"
out="$(python3 "$SCRIPT" --check "$TMP/p")" || fail "--check on a clean profile + small module must exit 0: $out"
[[ "$out" == *"profile check: ok"* ]] || fail "--check ok line: $out"
printf '\n## Execution groups\n\nProse that belongs in a reference module.\n' >> "$TMP/p/.context/testing-profile.md"
python3 - "$TMP/p/.context/references/testing/06-big.md" <<'PY'
import sys; open(sys.argv[1], "w").write("# Big\n\n" + "word " * 2600)
PY
if out="$(python3 "$SCRIPT" --check "$TMP/p")"; then fail "--check must exit 1 with findings: $out"; fi
[[ "$out" == *"prose section '## Execution groups'"* ]] || fail "--check must name the prose section: $out"
[[ "$out" == *"06-big.md is 2,602 words, over the 2,500-word tripwire"* ]] || fail "--check must name the module over the tripwire: $out"
[[ "$out" == *"01-small.md"* ]] && fail "--check must not report a module under the tripwire: $out"
[[ -e "$TMP/p/.context/testing-profile.md.bak" ]] && fail "--check must not write"

# --check resolves the profile the way sweep-gate.sh does (BL-365): .context/ normally,
# a tracked repo-root testing-profile.md as the fallback for a project that gitignores
# .context/ — aidex does, by policy, so its own --check reported the profile missing
# while the gate it shares the contract with read it fine.
mkdir -p "$TMP/r"
printf -- '---\nproject_slug: rooted\n---\n\n## Execution groups\n\nprose at the root.\n' > "$TMP/r/testing-profile.md"
if out="$(python3 "$SCRIPT" --check "$TMP/r")"; then fail "--check must read the root fallback and find its prose: $out"; fi
[[ "$out" == *"prose section '## Execution groups'"* ]] || fail "--check must report on the root profile, not call it missing: $out"
[[ "$out" == *"no profile at"* ]] && fail "--check must not call a root profile missing: $out"
# .context/ still wins when both exist: the root copy's prose must NOT be reported.
mkdir -p "$TMP/r/.context"
printf -- '---\nproject_slug: rooted\n---\n\nfacts only.\n' > "$TMP/r/.context/testing-profile.md"
out="$(python3 "$SCRIPT" --check "$TMP/r")" || fail "--check must prefer the clean .context/ profile: $out"
[[ "$out" == *"profile check: ok"* ]] || fail ".context/ must win over the root fallback: $out"
# Neither present: the refusal names both paths, like the gate's die.
mkdir -p "$TMP/n"
if out="$(python3 "$SCRIPT" --check "$TMP/n")"; then fail "--check with no profile must exit 1: $out"; fi
[[ "$out" == *"$TMP/n/.context/testing-profile.md"* && "$out" == *"$TMP/n/testing-profile.md"* ]] \
  || fail "the no-profile refusal must name both paths: $out"

# BL-364: the profile is composed from a stack-neutral core plus the keys each detected
# pack declares. A web project never sees a Postgres or Django key; a project with no
# recognised pack gets the core plus suite_cmd and nothing about ports, Vite or E2E.
python3 "$SCRIPT" --print "$TMP/w" | grep -qE "^(db_port|backend_test_cmd|seed_bootstrap_cmd|dev_backend_port):" \
  && fail "web fixture must carry no Django/Postgres key: $(python3 "$SCRIPT" --print "$TMP/w")"
python3 "$SCRIPT" --print "$TMP/w" | grep -qx "frontend_test_cmd: " || fail "web fixture must still carry the frontend keys"
mkdir -p "$TMP/bare"; printf 'echo tests\n' > "$TMP/bare/run-all.sh"
bare="$(python3 "$SCRIPT" --print "$TMP/bare")"
grep -qx "suite_cmd: " <<<"$bare" || fail "a project with no pack must carry suite_cmd: $bare"
grep -qx "testing_packs: " <<<"$bare" || fail "a project with no pack must still carry testing_packs: $bare"
grep -qE "^(db_port|dev_frontend_port|e2e_service|helpers_dir|ui_stack|backend_suite_cmd|e2e_detached):" <<<"$bare" \
  && fail "a project with no pack must carry no port, database, Vite or E2E key: $bare"
sed -n '/^---$/,/^---$/p' <<<"$bare" | grep -q "n/a" && fail "n/a is retired — an inapplicable key is omitted, never answered"
# The template and the script name the same keys, or one of them is lying.
TEMPLATE="$HERE/../assets/templates/testing-profile.md.template"
# Python, not sed|grep: under LC_ALL=C (the suite's locale) grep treated the template's
# non-ASCII group header as binary and stopped listing keys, so this passed in a shell
# and failed in the gate.
tkeys="$(python3 - "$TEMPLATE" <<'PYX'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
fm = t.split("---", 2)[1]
print("\n".join(sorted(k for k in re.findall(r"^([a-z_]+):", fm, re.M) if k not in ("title", "status", "created", "updated"))))
PYX
)"
skeys="$(python3 -c "import sys; sys.path.insert(0,'$HERE/../scripts'); import importlib; m=importlib.import_module('profile-init'); print('\n'.join(sorted(m.KEYS)))")"
[[ "$tkeys" == "$skeys" ]] || fail "template keys and profile-init KEYS differ:
$(diff <(echo "$tkeys") <(echo "$skeys"))"
grep -qE 'answered `n/a`, never left blank|answers `n/a` to every' "$TEMPLATE" && fail "the template still documents the n/a convention"

echo "OK — profile-init: facts read, blanks stay blank, overwrite refused, --print is read-only, --check finds prose and tripwire"
