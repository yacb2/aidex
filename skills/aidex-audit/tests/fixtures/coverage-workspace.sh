#!/usr/bin/env bash
# coverage-workspace.sh — builds a disposable two-repo workspace fixture for the
# test-coverage tooling, mirroring the NS Backoffice topology: the workspace root
# is NOT a git repo, `backend/` and `frontend/` each are, with committed files and
# a valid module-map.json covering the `billing` module and leaving `people`
# intentionally uncovered.
#
# Follows the temp-handling style of tests/test-scaffold.sh: the CALLER owns
# mktemp + trap cleanup. This script only builds the workspace and echoes its
# path.
#
# Usage: WS=$(bash skills/aidex-audit/tests/fixtures/coverage-workspace.sh)

set -euo pipefail

WS="$(mktemp -d)"

git_init_commit() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "initial commit"
}

# --- backend repo ---
mkdir -p "$WS/backend/apps/billing/tests"
mkdir -p "$WS/backend/apps/people"
cat > "$WS/backend/apps/billing/views.py" <<'EOF'
def invoice_list(request):
    return None
EOF
cat > "$WS/backend/apps/billing/tests/test_x.py" <<'EOF'
def test_a():
    assert True
EOF
cat > "$WS/backend/apps/people/views.py" <<'EOF'
def people_list(request):
    return None
EOF
git_init_commit "$WS/backend"

# --- frontend repo ---
mkdir -p "$WS/frontend/src/billing"
mkdir -p "$WS/frontend/tests/e2e/billing"
cat > "$WS/frontend/src/billing/Form.vue" <<'EOF'
<template><div /></template>
EOF
cat > "$WS/frontend/tests/e2e/billing/a.spec.ts" <<'EOF'
test('shows the invoice form', () => {});
test('submits the invoice form', () => {});
EOF
git_init_commit "$WS/frontend"

# --- module-map.json ---
mkdir -p "$WS/.context/audits/test-coverage"
cat > "$WS/.context/audits/test-coverage/module-map.json" <<'EOF'
{
  "version": 1,
  "repos": [
    { "name": "backend",  "path": "backend",  "test_hint": "cd backend && pytest {path}" },
    { "name": "frontend", "path": "frontend", "test_hint": "./test-e2e.sh {path}" }
  ],
  "modules": [
    {
      "id": "billing",
      "title": "Billing",
      "src": [
        "backend/apps/billing/**",
        "frontend/src/billing/**"
      ],
      "tests": {
        "unit": ["backend/apps/billing/tests/**"],
        "e2e":  ["frontend/tests/e2e/billing/**"]
      }
    },
    {
      "id": "people",
      "title": "People",
      "src": [
        "backend/apps/people/**"
      ],
      "tests": {
        "unit": [],
        "e2e": []
      }
    }
  ]
}
EOF

printf '%s\n' "$WS"
