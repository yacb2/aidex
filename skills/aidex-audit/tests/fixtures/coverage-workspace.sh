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
# Baseline commits are dated in the fixed past (2020) and drift commits in the
# fixed future (2099) so the coverage-sweep drift detector is deterministic: a
# matrix generated "now" sits strictly between them, so `--since=<matrix>` counts
# the drift commits and never the baseline — no sleeps, no wall-clock races.
#
# Usage:
#   WS=$(bash coverage-workspace.sh)                 # baseline only
#   WS=$(bash coverage-workspace.sh --drift)         # baseline + drift commits
#   bash coverage-workspace.sh --apply-drift "$WS"   # add drift to an existing WS
#                                                    # (lets a test snapshot the
#                                                    #  matrix BEFORE the drift)

set -euo pipefail

BASELINE_DATE="2020-01-01T00:00:00"
DRIFT_DATE="2099-01-01T00:00:00"

git_init_commit() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" add -A
  GIT_AUTHOR_DATE="$BASELINE_DATE" GIT_COMMITTER_DATE="$BASELINE_DATE" \
    git -C "$dir" commit -q -m "initial commit"
}

drift_commit() {
  local dir="$1"; shift
  GIT_AUTHOR_DATE="$DRIFT_DATE" GIT_COMMITTER_DATE="$DRIFT_DATE" \
    git -C "$dir" commit -q "$@"
}

build_workspace() {
  local WS="$1"

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
}

# apply_drift models "features shipped, tests didn't move": 3 src-only commits to
# billing's backend views (no test files touched) and 1 new frontend route file.
# Both repos change, so a correct sweep sums src commits across them.
apply_drift() {
  local WS="$1"
  local i
  for i in 1 2 3; do
    printf '\ndef extra_view_%s(request):\n    return None\n' "$i" \
      >> "$WS/backend/apps/billing/views.py"
    git -C "$WS/backend" add -A
    drift_commit "$WS/backend" -m "billing: ship feature $i (no tests)"
  done

  cat > "$WS/frontend/src/billing/NewView.vue" <<'EOF'
<template><div>new</div></template>
EOF
  git -C "$WS/frontend" add -A
  drift_commit "$WS/frontend" -m "billing: new route NewView.vue (no tests)"
}

MODE="${1:-}"

if [[ "$MODE" == "--apply-drift" ]]; then
  WS="${2:?--apply-drift requires an existing workspace path}"
  apply_drift "$WS"
  exit 0
fi

WS="$(mktemp -d)"
build_workspace "$WS"

if [[ "$MODE" == "--drift" ]]; then
  apply_drift "$WS"
fi

printf '%s\n' "$WS"
