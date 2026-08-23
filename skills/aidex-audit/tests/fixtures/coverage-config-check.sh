#!/usr/bin/env bash
# coverage-config-check.sh (fixtures) — builds a disposable workspace of five
# tiny project trees exercising config_check.py's traps and the clean case.
# Follows the temp-handling style of coverage-workspace.sh: the CALLER owns
# mktemp + trap cleanup. This script only builds the workspace and echoes its
# path. Each project is a directory under the workspace root — no git repo
# needed, config_check.py never touches git.
#
# Usage: WS=$(bash coverage-config-check.sh)
#
# Projects built:
#   e2e-only          hasher_e2e present, hasher_pytest absent (no settings module
#                      defines PASSWORD_HASHERS at all) -> must report drift, not clean
#   bad-settings-path  DJANGO_SETTINGS_MODULE names a module that does not exist
#                      under backend/ -> hasher_pytest = unresolvable, not skipped
#   two-entry-hasher   hasher_e2e is MD5 first, PBKDF2 second -> must be `present`,
#                      never penalized for the second entry
#   provider-no-pkg    vitest.config.ts declares coverage.provider but package.json
#                      has no @vitest/coverage-v8 -> coverage_provider = absent
#   clean              every key compliant

set -euo pipefail

WS="$(mktemp -d)"

mkpy() { mkdir -p "$(dirname "$1")"; cat >"$1"; }

# ---------------------------------------------------------------------------
# e2e-only: hasher_e2e present, hasher_pytest absent
# ---------------------------------------------------------------------------
P="$WS/e2e-only"
mkpy "$P/backend/pyproject.toml" <<'EOF'
[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "config.settings.dev"
EOF
mkpy "$P/backend/config/settings/dev.py" <<'EOF'
DEBUG = True
EOF
mkpy "$P/backend/config/settings/test_e2e.py" <<'EOF'
PASSWORD_HASHERS = ['django.contrib.auth.hashers.MD5PasswordHasher']
EOF

# ---------------------------------------------------------------------------
# bad-settings-path: DJANGO_SETTINGS_MODULE does not resolve to a file
# ---------------------------------------------------------------------------
P="$WS/bad-settings-path"
mkpy "$P/backend/pyproject.toml" <<'EOF'
[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "core.settings"
EOF
mkpy "$P/backend/config/settings/dev.py" <<'EOF'
DEBUG = True
EOF
# no backend/core/settings.py or backend/core/settings/__init__.py anywhere

# ---------------------------------------------------------------------------
# two-entry-hasher: hasher_e2e is MD5 first, PBKDF2 second (must pass)
# ---------------------------------------------------------------------------
P="$WS/two-entry-hasher"
mkpy "$P/backend/pyproject.toml" <<'EOF'
[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "config.settings.dev"
EOF
mkpy "$P/backend/config/settings/dev.py" <<'EOF'
DEBUG = True
EOF
mkpy "$P/backend/config/settings/test_e2e.py" <<'EOF'
PASSWORD_HASHERS = [
    'django.contrib.auth.hashers.MD5PasswordHasher',
    'django.contrib.auth.hashers.PBKDF2PasswordHasher',
]
EOF

# ---------------------------------------------------------------------------
# provider-no-pkg: coverage.provider declared, no @vitest/coverage-v8 package
# ---------------------------------------------------------------------------
P="$WS/provider-no-pkg"
mkpy "$P/frontend/vitest.config.ts" <<'EOF'
export default {
  test: {
    include: ['src/**/*.spec.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text'],
    },
  },
}
EOF
mkpy "$P/frontend/package.json" <<'EOF'
{
  "name": "provider-no-pkg-frontend",
  "devDependencies": {
    "vitest": "^4.0.0"
  }
}
EOF

# ---------------------------------------------------------------------------
# ci-n-auto: -n auto lives in .github/workflows/ci.yml — hidden dir, the exact
# place it lingers in the field. A walk that prunes every dot-directory reads
# this project compliant (weekend review 2026-08-23, finding 1).
# ---------------------------------------------------------------------------
P="$WS/ci-n-auto"
mkpy "$P/.github/workflows/ci.yml" <<'EOF'
jobs:
  test:
    steps:
      - run: pytest -n auto backend/
EOF

# ---------------------------------------------------------------------------
# custom-hasher-first: a NON-django.contrib hasher first, MD5 second. The
# check exists to catch a slow hasher running first under pytest; an entry
# regex pinned to django.contrib.* skips the real first entry and reports
# MD5-first (weekend review 2026-08-23, finding 2).
# ---------------------------------------------------------------------------
P="$WS/custom-hasher-first"
mkpy "$P/backend/pyproject.toml" <<'EOF'
[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "config.settings.test"
EOF
mkpy "$P/backend/config/settings/test.py" <<'EOF'
PASSWORD_HASHERS = [
    "myproj.hashers.SlowCustomHasher",
    "django.contrib.auth.hashers.MD5PasswordHasher",
]
EOF

# ---------------------------------------------------------------------------
# clean: every key compliant
# ---------------------------------------------------------------------------
P="$WS/clean"
mkpy "$P/backend/pyproject.toml" <<'EOF'
[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "config.settings.test"
EOF
mkpy "$P/backend/config/settings/dev.py" <<'EOF'
DEBUG = True
EOF
mkpy "$P/backend/config/settings/test.py" <<'EOF'
from .dev import *
PASSWORD_HASHERS = ['django.contrib.auth.hashers.MD5PasswordHasher']
EOF
mkpy "$P/backend/config/settings/test_e2e.py" <<'EOF'
PASSWORD_HASHERS = ['django.contrib.auth.hashers.MD5PasswordHasher']
EOF
mkpy "$P/frontend/vitest.config.ts" <<'EOF'
export default {
  test: {
    include: ['src/**/*.spec.ts'],
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
      reporter: ['text'],
    },
  },
}
EOF
mkpy "$P/frontend/package.json" <<'EOF'
{
  "name": "clean-frontend",
  "devDependencies": {
    "@vitest/coverage-v8": "^4.1.7"
  }
}
EOF

printf '%s\n' "$WS"
