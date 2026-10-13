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
[[ "$out" == *"wrote $TMP/p/.context/profiles/testing.md"* ]] || fail "did not report the written path: $out"
prof="$TMP/p/.context/profiles/testing.md"
for kv in "project_slug: demo_app" "project_kebab: demo-app" "db_port: 5600" "db_user: demo_user" \
          "dev_frontend_port: 3600" "dev_backend_port: 8600" "e2e_frontend_port: 3610" "e2e_backend_port: 8610" \
          "e2e_service: backend-test" "seed_e2e_bootstrap_cmd: bootstrap_e2e_data" \
          "backend_test_cmd: docker compose exec -T backend pytest {path}" "e2e_test_cmd: ./test-e2e.sh {spec}" \
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
rm "$prof"; python3 "$SCRIPT" --print "$TMP/p" | grep >/dev/null "^project_slug: demo_app$" || fail "--print output"
[[ -e "$prof" ]] && fail "--print must not write"
# A web project (no backend/, root package.json) resolves the web packs, never the app ones.
mkdir -p "$TMP/w"
printf '{"dependencies":{"payload":"^3","svelte":"^5"},"devDependencies":{"vitest":"^4","@playwright/test":"^1"}}\n' > "$TMP/w/package.json"
python3 "$SCRIPT" --print "$TMP/w" | grep >/dev/null -x "testing_packs: testing-payload testing-svelte testing-playwright-web" \
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
printf '\n## Execution groups\n\nProse that belongs in a reference module.\n' >> "$TMP/p/.context/profiles/testing.md"
python3 - "$TMP/p/.context/references/testing/06-big.md" <<'PY'
import sys; open(sys.argv[1], "w").write("# Big\n\n" + "word " * 2600)
PY
if out="$(python3 "$SCRIPT" --check "$TMP/p")"; then fail "--check must exit 1 with findings: $out"; fi
[[ "$out" == *"prose section '## Execution groups'"* ]] || fail "--check must name the prose section: $out"
[[ "$out" == *"06-big.md is 2,602 words, over the 2,500-word tripwire"* ]] || fail "--check must name the module over the tripwire: $out"
[[ "$out" == *"01-small.md"* ]] && fail "--check must not report a module under the tripwire: $out"
[[ -e "$TMP/p/.context/profiles/testing.md.bak" ]] && fail "--check must not write"

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
mkdir -p "$TMP/r/.context/profiles"
printf -- '---\nproject_slug: rooted\n---\n\nfacts only.\n' > "$TMP/r/.context/profiles/testing.md"
out="$(python3 "$SCRIPT" --check "$TMP/r")" || fail "--check must prefer the clean .context/ profile: $out"
[[ "$out" == *"profile check: ok"* ]] || fail ".context/ must win over the root fallback: $out"
# Neither present: the refusal names both paths, like the gate's die.
mkdir -p "$TMP/n"
if out="$(python3 "$SCRIPT" --check "$TMP/n")"; then fail "--check with no profile must exit 1: $out"; fi
[[ "$out" == *"$TMP/n/.context/profiles/testing.md"* && "$out" == *"$TMP/n/testing-profile.md"* ]] \
  || fail "the no-profile refusal must name both paths: $out"

# BL-364: the profile is composed from a stack-neutral core plus the keys each detected
# pack declares. A web project never sees a Postgres or Django key; a project with no
# recognised pack gets the core plus suite_cmd and nothing about ports, Vite or E2E.
python3 "$SCRIPT" --print "$TMP/w" | grep >/dev/null -E "^(db_port|backend_test_cmd|seed_bootstrap_cmd|dev_backend_port):" \
  && fail "web fixture must carry no Django/Postgres key: $(python3 "$SCRIPT" --print "$TMP/w")"
# The web fixture's vitest sits in the ROOT package.json (no lockfile): the command runs
# there, with no `cd frontend` (LOOP-013 coverage-c09).
python3 "$SCRIPT" --print "$TMP/w" | grep >/dev/null -x "frontend_test_cmd: npm exec vitest run {path}" \
  || fail "web fixture: vitest in the root package.json must seed the root command: $(python3 "$SCRIPT" --print "$TMP/w" | grep frontend_test_cmd)"
mkdir -p "$TMP/bare"; printf 'echo tests\n' > "$TMP/bare/run-all.sh"
bare="$(python3 "$SCRIPT" --print "$TMP/bare")"
grep -qx "suite_cmd: " <<<"$bare" || fail "a project with no pack must carry suite_cmd: $bare"
grep -qx "testing_packs: " <<<"$bare" || fail "a project with no pack must still carry testing_packs: $bare"
grep -qE "^(db_port|dev_frontend_port|e2e_service|helpers_dir|ui_stack|backend_suite_cmd|e2e_detached):" <<<"$bare" \
  && fail "a project with no pack must carry no port, database, Vite or E2E key: $bare"
sed -n '/^---$/,/^---$/p' <<<"$bare" | grep >/dev/null "n/a" && fail "n/a is retired — an inapplicable key is omitted, never answered"
# The template and the script name the same keys, or one of them is lying.
TEMPLATE="$HERE/../assets/templates/testing.md.template"
# Python, not sed|grep: under LC_ALL=C (the suite's locale) grep treated the template's
# non-ASCII group header as binary and stopped listing keys, so this passed in a shell
# and failed in the gate.
tkeys="$(python3 - "$TEMPLATE" <<'PYX'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
fm = t.split("---", 2)[1]
print("\n".join(sorted(k for k in re.findall(r"^([a-z0-9_]+):", fm, re.M) if k not in ("title", "status", "created", "updated"))))
PYX
)"
skeys="$(python3 -c "import sys; sys.path.insert(0,'$HERE/../scripts'); import importlib; m=importlib.import_module('profile-init'); print('\n'.join(sorted(m.KEYS)))")"
[[ "$tkeys" == "$skeys" ]] || fail "template keys and profile-init KEYS differ:
$(diff <(echo "$tkeys") <(echo "$skeys"))"
grep -qE 'answered `n/a`, never left blank|answers `n/a` to every' "$TEMPLATE" && fail "the template still documents the n/a convention"

# A legacy-root profile counts as existing: the seed refuses, names it, writes nothing new.
mkdir -p "$TMP/lg/.context"; printf 'legacy\n' > "$TMP/lg/.context/testing-profile.md"
if out="$(python3 "$SCRIPT" "$TMP/lg" 2>&1)"; then fail "seeding over a legacy-root profile must refuse: $out"; fi
[[ "$out" == *"$TMP/lg/.context/testing-profile.md"* ]] || fail "the refusal must name the legacy file: $out"
[[ ! -e "$TMP/lg/.context/profiles" ]] || fail "the refusal still wrote profiles/"

# --- LOOP-013 module review (coverage-c01..c13): one case per confirmed finding ---

# c01: a tracked repo-root testing-profile.md is a profile too (BL-289). Seeding refuses
# instead of writing a blank .context/ profile that would shadow the curated one.
mkdir -p "$TMP/rt"; printf -- '---\nproject_slug: curated\n---\n' > "$TMP/rt/testing-profile.md"
if out="$(python3 "$SCRIPT" "$TMP/rt" 2>&1)"; then fail "seeding over a root testing-profile.md must refuse: $out"; fi
[[ "$out" == *"$TMP/rt/testing-profile.md"* ]] || fail "the refusal must name the root profile: $out"
[[ ! -e "$TMP/rt/.context" ]] || fail "the refusal still wrote .context/"
# ...and it must not send the reader to --force, which writes a second profile that wins.
[[ "$out" == *"--force would write a second one"* && "$out" != *"(use --force)"* ]] \
  || fail "the refusal must say --force would shadow the root profile: $out"

# c02: a `---` rule in the body must not hide the prose above it from --check.
mkdir -p "$TMP/hr/.context/profiles"
printf -- '---\nproject_slug: foo\n---\n\n## Rules\n\nprose.\n\n---\n\nFooter note.\n' > "$TMP/hr/.context/profiles/testing.md"
if out="$(python3 "$SCRIPT" --check "$TMP/hr")"; then fail "a body rule hid the prose section from --check: $out"; fi
[[ "$out" == *"prose section '## Rules'"* ]] || fail "--check must name the section above the body rule: $out"

# c03: dev_backend_port comes from the backend service, never from whichever service
# maps a port first (Postgres listed before backend gave 5432).
mkdir -p "$TMP/c3/backend"; printf '[tool.pytest.ini_options]\n' > "$TMP/c3/backend/pyproject.toml"
printf 'services:\n  db:\n    image: postgres\n    ports:\n      - "5432:5432"\n  backend:\n    ports:\n      - "8000:8000"\n' > "$TMP/c3/docker-compose.yml"
python3 "$SCRIPT" --print "$TMP/c3" | grep >/dev/null -x "dev_backend_port: 8000" \
  || fail "dev_backend_port must come from the backend service: $(python3 "$SCRIPT" --print "$TMP/c3" | grep dev_backend_port)"
printf 'services:\n  redis:\n    ports:\n      - "6379:6379"\n  backend:\n    build: .\n' > "$TMP/c3/docker-compose.yml"
python3 "$SCRIPT" --print "$TMP/c3" | grep >/dev/null -x "dev_backend_port: " \
  || fail "a backend service with no port leaves dev_backend_port blank: $(python3 "$SCRIPT" --print "$TMP/c3" | grep dev_backend_port)"

# c08: backend_test_cmd names a compose service that exists and a runner the files
# declare; otherwise it stays blank. (`manage.py test` cannot take a file path.)
mkdir -p "$TMP/c8/backend"; printf '[tool.pytest.ini_options]\n' > "$TMP/c8/backend/pyproject.toml"
printf 'services:\n  api:\n    build: .\n' > "$TMP/c8/docker-compose.yml"
python3 "$SCRIPT" --print "$TMP/c8" | grep >/dev/null -x "backend_test_cmd: " \
  || fail "no backend service in compose: backend_test_cmd must stay blank: $(python3 "$SCRIPT" --print "$TMP/c8" | grep backend_test_cmd)"
printf 'services:\n  backend:\n    build: .\n' > "$TMP/c8/docker-compose.yml"
printf '[project]\nname = "x"  # tests: pytest some day\n' > "$TMP/c8/backend/pyproject.toml"
python3 "$SCRIPT" --print "$TMP/c8" | grep >/dev/null -x "backend_test_cmd: " \
  || fail "no declared runner (pytest only in a comment): backend_test_cmd must stay blank: $(python3 "$SCRIPT" --print "$TMP/c8" | grep backend_test_cmd)"

# c09: the frontend command follows the package.json that declares vitest, and pnpm
# follows a pnpm lockfile at that package or at the repo root.
mkdir -p "$TMP/c9"; : > "$TMP/c9/pnpm-lock.yaml"
printf '{"dependencies":{"vue":"^3","reka-ui":"^2"},"devDependencies":{"vitest":"^4"}}\n' > "$TMP/c9/package.json"
c9="$(python3 "$SCRIPT" --print "$TMP/c9")"
grep -qx "frontend_test_cmd: pnpm vitest run {path}" <<<"$c9" || fail "root vue+vitest with a root pnpm lock: $c9"
grep -qx "ui_stack: reka-ui" <<<"$c9" || fail "ui_stack must read the package that declares it: $c9"
rm "$TMP/c9/package.json"; mkdir -p "$TMP/c9/frontend"
printf '{"dependencies":{"vue":"^3"},"devDependencies":{"vitest":"^4"}}\n' > "$TMP/c9/frontend/package.json"
python3 "$SCRIPT" --print "$TMP/c9" | grep >/dev/null -x "frontend_test_cmd: cd frontend && pnpm vitest run {path}" \
  || fail "frontend vitest under a root pnpm lock must use pnpm: $(python3 "$SCRIPT" --print "$TMP/c9" | grep frontend_test_cmd)"

# c13: packs come from dependency keys, never from a token anywhere in package.json.
mkdir -p "$TMP/c13/frontend"
printf '{"name":"x","keywords":["vue","payload"],"dependencies":{"react":"^18"}}\n' > "$TMP/c13/frontend/package.json"
python3 "$SCRIPT" --print "$TMP/c13" | grep >/dev/null -x "testing_packs: " \
  || fail "a keyword is not a dependency: $(python3 "$SCRIPT" --print "$TMP/c13" | grep testing_packs)"

# c10: the profile and the script's output are UTF-8 whatever the locale (the note and
# the report carry an em dash). PYTHONIOENCODING is unset so stdout gets the locale's
# ASCII, the finding's own scenario.
mkdir -p "$TMP/c10"
ascii() { env -u PYTHONIOENCODING LC_ALL=C PYTHONCOERCECLOCALE=0 PYTHONUTF8=0 python3 "$SCRIPT" "$@"; }
ascii "$TMP/c10" >/dev/null 2>"$TMP/c10.err" \
  || fail "seeding under an ASCII locale must exit 0: $(tail -1 "$TMP/c10.err")"
ascii --print "$TMP/c10" >/dev/null 2>"$TMP/c10.err" \
  || fail "--print under an ASCII locale must exit 0: $(tail -1 "$TMP/c10.err")"
grep -q "package.json —" "$TMP/c10/.context/profiles/testing.md" || fail "the written profile lost its note"

# c11: the slug regexes accept the ${VAR:-default} form the port and user regexes do.
mkdir -p "$TMP/c11a" "$TMP/c11b"
printf 'export DB_E2E="${DB_E2E:-myapp_e2e}"\n' > "$TMP/c11a/test-e2e.sh"
printf 'DB_TEMPLATE="${DB_TEMPLATE:-other_e2e_template}"\n' > "$TMP/c11b/test-e2e.sh"
python3 "$SCRIPT" --print "$TMP/c11a" | grep >/dev/null -x "project_slug: myapp" \
  || fail "DB_E2E=\${DB_E2E:-myapp_e2e} must give the slug: $(python3 "$SCRIPT" --print "$TMP/c11a" | grep project_slug)"
python3 "$SCRIPT" --print "$TMP/c11b" | grep >/dev/null -x "project_slug: other" \
  || fail "DB_TEMPLATE=\${DB_TEMPLATE:-other_e2e_template} must give the slug: $(python3 "$SCRIPT" --print "$TMP/c11b" | grep project_slug)"

# c12: an empty profile is reported as empty, not as missing.
mkdir -p "$TMP/c12/.context/profiles"; : > "$TMP/c12/.context/profiles/testing.md"
if out="$(python3 "$SCRIPT" --check "$TMP/c12")"; then fail "--check on an empty profile must exit 1: $out"; fi
[[ "$out" == *"empty"* && "$out" != *"no profile at"* ]] || fail "an empty profile must be reported as empty, not missing: $out"

# c08/c09 branches, one row each (review of the first fix: no row could go red).
# (a) frontend/ and the root both declare vitest: frontend/ wins.
mkdir -p "$TMP/v2/frontend"
printf '{"dependencies":{"vue":"^3"},"devDependencies":{"vitest":"^4"}}\n' > "$TMP/v2/frontend/package.json"
printf '{"devDependencies":{"vitest":"^4"}}\n' > "$TMP/v2/package.json"
python3 "$SCRIPT" --print "$TMP/v2" | grep >/dev/null -x "frontend_test_cmd: cd frontend && npm exec vitest run {path}" \
  || fail "frontend/ must win over the root: $(python3 "$SCRIPT" --print "$TMP/v2" | grep frontend_test_cmd)"
# (b) cms/ and web/ both declare vitest, no frontend/: nothing decides, so blank.
mkdir -p "$TMP/v3/cms" "$TMP/v3/web"
printf '{"dependencies":{"vue":"^3"},"devDependencies":{"vitest":"^4"}}\n' > "$TMP/v3/cms/package.json"
printf '{"devDependencies":{"vitest":"^4"}}\n' > "$TMP/v3/web/package.json"
python3 "$SCRIPT" --print "$TMP/v3" | grep >/dev/null -x "frontend_test_cmd: " \
  || fail "two non-frontend vitest packages must leave the key blank: $(python3 "$SCRIPT" --print "$TMP/v3" | grep frontend_test_cmd)"
# (c) poetry dev group and (d) a PEP 621 optional-dependencies array declare pytest.
mkdir -p "$TMP/py/backend"; printf 'services:\n  backend:\n    build: .\n' > "$TMP/py/docker-compose.yml"
for decl in '[tool.poetry.group.dev.dependencies]\npytest = "^8"\n' '[project.optional-dependencies]\ndev = ["pytest>=8"]\n'; do
  printf "$decl" > "$TMP/py/backend/pyproject.toml"
  python3 "$SCRIPT" --print "$TMP/py" | grep >/dev/null -x "backend_test_cmd: docker compose exec -T backend pytest {path}" \
    || fail "pytest declared as $(head -1 "$TMP/py/backend/pyproject.toml"): $(python3 "$SCRIPT" --print "$TMP/py" | grep backend_test_cmd)"
done

# service_block(): one row per compose shape. Columns: label | compose (printf format) |
# expected dev_backend_port | `y` when backend_test_cmd is the pytest command, `-` when
# blank. The pyproject declares pytest in every row, so the command turns on the service.
mkdir -p "$TMP/sb/backend"; printf '[tool.pytest.ini_options]\n' > "$TMP/sb/backend/pyproject.toml"
while IFS='|' read -r label compose port cmd; do
  printf "$compose" > "$TMP/sb/docker-compose.yml"
  sb="$(python3 "$SCRIPT" --print "$TMP/sb")"
  want=""; if [[ "$cmd" == y ]]; then want="docker compose exec -T backend pytest {path}"; fi
  grep -qxF "dev_backend_port: $port" <<<"$sb" && grep -qxF "backend_test_cmd: $want" <<<"$sb" \
    || fail "service_block row '$label': want port '$port', cmd '$want'; got $(grep -E '^(dev_backend_port|backend_test_cmd):' <<<"$sb" | paste -sd';' -)"
done <<'ROWS'
anchor after the key|services:\n  backend: &be\n    ports:\n      - "8000:8000"\n|8000|y
trailing comment after the key|services:\n  backend:  # django\n    ports:\n      - "8001:8001"\n|8001|y
quoted key|services:\n  "backend":\n    ports:\n      - "8002:8002"\n|8002|y
comment after services:|services: # all\n  backend:\n    ports:\n      - "8003:8003"\n|8003|y
column-4 comment first under services:|services:\n    # a column-4 comment\n  backend:\n    ports:\n      - "8004:8004"\n|8004|y
column-0 comment inside services:|services:\n  db:\n    image: postgres\n# a column-0 comment\n  backend:\n    ports:\n      - "8005:8005"\n|8005|y
block stops at the next service|services:\n  backend:\n    build: .\n  db:\n    ports:\n      - "5432:5432"\n||y
a backend key outside services:|networks:\n  backend:\n    driver: bridge\nservices:\n  api:\n    ports:\n      - "8000:8000"\n||-
exact key, not a prefix|services:\n  backend-test:\n    ports:\n      - "8610:8600"\n  backend:\n    build: .\n||y
anchor on services: (BL-783 j)|services: &svc\n  backend:\n    ports:\n      - "8006:8006"\n|8006|y
UTF-8 BOM before services:|\xef\xbb\xbfservices:\n  backend:\n    ports:\n      - "8000:8000"\n|8000|y
ROWS

# deps(): a UTF-8 BOM is still JSON, and a top-level array is not a package.
mkdir -p "$TMP/bom/frontend"
printf '\xef\xbb\xbf{"dependencies":{"vue":"^3"}}\n' > "$TMP/bom/frontend/package.json"
python3 "$SCRIPT" --print "$TMP/bom" | grep >/dev/null -x "testing_packs: testing-vue" \
  || fail "a BOM-prefixed package.json must still be read: $(python3 "$SCRIPT" --print "$TMP/bom" 2>&1 | grep -E 'testing_packs|Error')"
printf '[]\n' > "$TMP/bom/frontend/package.json"
out="$(python3 "$SCRIPT" --print "$TMP/bom" 2>&1)" || fail "a top-level [] package.json must not crash: $(tail -1 <<<"$out")"
grep -qx "testing_packs: " <<<"$out" || fail "a top-level [] declares no dependency: $out"

# c12 edge: a profile of blank lines is empty too.
printf '\n  \n\n' > "$TMP/c12/.context/profiles/testing.md"
if out="$(python3 "$SCRIPT" --check "$TMP/c12")"; then fail "--check on a whitespace-only profile must exit 1: $out"; fi
[[ "$out" == *"empty"* ]] || fail "a whitespace-only profile must be reported as empty: $out"

# --- BL-783: one row per edge left open by the coverage fix unit ---
p783() { python3 "$SCRIPT" --print "$1" 2>&1; }
# (a) e2e_service is a key of `services:`, at whatever indent, never a key elsewhere.
mkdir -p "$TMP/a783"; echo x > "$TMP/a783/test-e2e.sh"
printf 'networks:\n  backend-test:\n    driver: bridge\nservices:\n  backend:\n    build: .\n' > "$TMP/a783/docker-compose.yml"
grep -qx "e2e_service: " <<<"$(p783 "$TMP/a783")" \
  || fail "(a) a networks key is not a service: $(p783 "$TMP/a783" | grep e2e_service)"
printf 'services:\n    backend:\n        build: .\n    backend-test:\n        build: .\n' > "$TMP/a783/docker-compose.yml"
grep -qx "e2e_service: backend-test" <<<"$(p783 "$TMP/a783")" \
  || fail "(a) a 4-space-indented service must be found: $(p783 "$TMP/a783" | grep e2e_service)"
# ...and a nested key under a service is not a service (review r1 point 2).
printf 'services:\n  backend:\n    depends_on:\n      backend-test-db:\n        condition: service_healthy\n  backend-test:\n    build: .\n' > "$TMP/a783/docker-compose.yml"
grep -qx "e2e_service: backend-test" <<<"$(p783 "$TMP/a783")" \
  || fail "(a) a nested depends_on key is not a service: $(p783 "$TMP/a783" | grep e2e_service)"
# (b) ${BACKEND_PORT:-N} counts only inside the backend service.
mkdir -p "$TMP/b783/backend"; : > "$TMP/b783/backend/manage.py"
printf 'services:\n  proxy:\n    ports:\n      - "${BACKEND_PORT:-9999}:80"\n  backend:\n    ports:\n      - "8000:8000"\n' > "$TMP/b783/docker-compose.yml"
grep -qx "dev_backend_port: 8000" <<<"$(p783 "$TMP/b783")" \
  || fail "(b) BACKEND_PORT of another service: $(p783 "$TMP/b783" | grep dev_backend_port)"
# ...yet with no port in the backend block, BACKEND_PORT anywhere still answers: the
# order is BACKEND_PORT in backend, a number in backend, BACKEND_PORT anywhere (review r1 point 6).
mkdir -p "$TMP/b783api/backend"; : > "$TMP/b783api/backend/manage.py"
printf 'services:\n  api:\n    ports:\n      - "${BACKEND_PORT:-8000}:8000"\n' > "$TMP/b783api/docker-compose.yml"
grep -qx "dev_backend_port: 8000" <<<"$(p783 "$TMP/b783api")" \
  || fail "(b) BACKEND_PORT on a service named api: $(p783 "$TMP/b783api" | grep dev_backend_port)"
# (c) the fallback reads a host port of any width.
for hp in 18000 80; do
  printf 'services:\n  backend:\n    ports:\n      - "%s:8000"\n' "$hp" > "$TMP/b783/docker-compose.yml"
  grep -qx "dev_backend_port: $hp" <<<"$(p783 "$TMP/b783")" \
    || fail "(c) host port $hp: $(p783 "$TMP/b783" | grep dev_backend_port)"
done
# (d) compose.yml is read like docker compose reads it, and wins over docker-compose.yml.
mkdir -p "$TMP/d783/backend"; : > "$TMP/d783/backend/manage.py"
printf 'services:\n  backend:\n    ports:\n      - "8100:8000"\n' > "$TMP/d783/compose.yml"
grep -qx "dev_backend_port: 8100" <<<"$(p783 "$TMP/d783")" \
  || fail "(d) compose.yml alone: $(p783 "$TMP/d783" | grep dev_backend_port)"
printf 'services:\n  backend:\n    ports:\n      - "8200:8000"\n' > "$TMP/d783/docker-compose.yml"
grep -qx "dev_backend_port: 8100" <<<"$(p783 "$TMP/d783")" \
  || fail "(d) compose.yml must win over docker-compose.yml: $(p783 "$TMP/d783" | grep dev_backend_port)"
# compose.yaml is read alone, and wins over compose.yml (review r1 point 3).
printf 'services:\n  backend:\n    ports:\n      - "8300:8000"\n' > "$TMP/d783/compose.yaml"
grep -qx "dev_backend_port: 8300" <<<"$(p783 "$TMP/d783")" \
  || fail "(d) compose.yaml must win over compose.yml: $(p783 "$TMP/d783" | grep dev_backend_port)"
mkdir -p "$TMP/d783y/backend"; : > "$TMP/d783y/backend/manage.py"; cp "$TMP/d783/compose.yaml" "$TMP/d783y/"
grep -qx "dev_backend_port: 8300" <<<"$(p783 "$TMP/d783y")" \
  || fail "(d) compose.yaml alone: $(p783 "$TMP/d783y" | grep dev_backend_port)"
# (f) pytest declared only in backend/requirements.txt is a declared runner.
mkdir -p "$TMP/f783/backend"; : > "$TMP/f783/backend/manage.py"
printf 'services:\n  backend:\n    build: .\n' > "$TMP/f783/docker-compose.yml"
printf 'django>=5\n# pytest-xdist later\npytest==8.3\n' > "$TMP/f783/backend/requirements.txt"
grep -qx "backend_test_cmd: docker compose exec -T backend pytest {path}" <<<"$(p783 "$TMP/f783")" \
  || fail "(f) pytest in requirements.txt: $(p783 "$TMP/f783" | grep backend_test_cmd)"
printf 'django>=5\n# pytest some day\n' > "$TMP/f783/backend/requirements.txt"
grep -qx "backend_test_cmd: " <<<"$(p783 "$TMP/f783")" \
  || fail "(f) pytest only in a requirements comment: $(p783 "$TMP/f783" | grep backend_test_cmd)"
# Any backend/requirements*.txt counts, and a root with glob characters is still found
# (review r1 point 4).
printf 'pytest-django==4.9\n' > "$TMP/f783/backend/requirements-dev.txt"
grep -qx "backend_test_cmd: docker compose exec -T backend pytest {path}" <<<"$(p783 "$TMP/f783")" \
  || fail "(f) pytest-django in requirements-dev.txt: $(p783 "$TMP/f783" | grep backend_test_cmd)"
mkdir -p "$TMP/proj[1]"; cp -R "$TMP/f783/." "$TMP/proj[1]/"
grep -qx "backend_test_cmd: docker compose exec -T backend pytest {path}" <<<"$(p783 "$TMP/proj[1]")" \
  || fail "(f) a project dir named proj[1]: $(p783 "$TMP/proj[1]" | grep backend_test_cmd)"
# (g) a profile whose front matter holds no key states no fact: it is empty too.
mkdir -p "$TMP/g783/.context/profiles"; printf -- '---\n---\n' > "$TMP/g783/.context/profiles/testing.md"
if out="$(python3 "$SCRIPT" --check "$TMP/g783")"; then fail "(g) --check on a keyless front matter must exit 1: $out"; fi
[[ "$out" == *"no key"* ]] || fail "(g) the finding must say the front matter holds no key: $out"
# (h) a quoted "pytest" or a [tool.pytest table inside a pyproject comment declares nothing.
mkdir -p "$TMP/h783/backend"; printf 'services:\n  backend:\n    build: .\n' > "$TMP/h783/docker-compose.yml"
for decl in '[project]\nname = "x"  # "pytest" later\n' '# [tool.pytest.ini_options]\n[project]\nname = "x"\n'; do
  printf "$decl" > "$TMP/h783/backend/pyproject.toml"
  grep -qx "backend_test_cmd: " <<<"$(p783 "$TMP/h783")" \
    || fail "(h) pytest only in a comment of $(paste -sd' ' "$TMP/h783/backend/pyproject.toml"): $(p783 "$TMP/h783" | grep backend_test_cmd)"
done
# ...but a `#` inside a value (a URL fragment) is not a comment, and a comment line does
# not hide the declaration after it (review r1 points 1 and 5).
for decl in '[project]\ndependencies = ["lib @ git+https://h/x.git#egg=lib", "pytest>=8"]\n' '# dev tooling\n[tool.pytest.ini_options]\n'; do
  printf "$decl" > "$TMP/h783/backend/pyproject.toml"
  grep -qx "backend_test_cmd: docker compose exec -T backend pytest {path}" <<<"$(p783 "$TMP/h783")" \
    || fail "(h) pytest declared in $(paste -sd' ' "$TMP/h783/backend/pyproject.toml"): $(p783 "$TMP/h783" | grep backend_test_cmd)"
done
# (i) dependencies that are not an object declare nothing: `5` must not crash, `["vue"]`
# must not yield a pack. The "vue" string row was green before the fix: it pins that a
# string dependency is not split into names (npm's legacy normalize-package-data would).
mkdir -p "$TMP/i783"
for d in '5' '["vue"]' '"vue"'; do
  printf '{"dependencies":%s}\n' "$d" > "$TMP/i783/package.json"
  out="$(p783 "$TMP/i783")" || fail "(i) dependencies $d must not crash: $(tail -1 <<<"$out")"
  grep -qx "testing_packs: " <<<"$out" || fail "(i) dependencies $d declare no pack: $(grep testing_packs <<<"$out")"
done
# (j) a top-level `services: &anchor` still opens the services (the service_block table
# pins the port; this row pins e2e_service). Flow style and tab indents: see the hand-back.
mkdir -p "$TMP/j783"; echo x > "$TMP/j783/test-e2e.sh"
printf 'services: &svc\n  backend-test:\n    build: .\n' > "$TMP/j783/docker-compose.yml"
grep -qx "e2e_service: backend-test" <<<"$(p783 "$TMP/j783")" \
  || fail "(j) services: &anchor: $(p783 "$TMP/j783" | grep e2e_service)"

echo "OK — profile-init: facts read, blanks stay blank, overwrite refused, --print is read-only, --check finds prose and tripwire"
