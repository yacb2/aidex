#!/usr/bin/env bash
# A folder under audits/ is not a methodology just by being a folder.
#
# `audits/test-coverage/` is where the coverage playbook keeps module-map.json,
# coverage-matrix.md and defect-prone.jsonl. The path is hard-coded in
# coverage/defect_prone.py, in references 06 and 07, and in test-defect-prone.sh,
# so it cannot move; and validate-audit.sh special-cases it as a data directory in
# its own coverage checks. It also demanded three methodology boards there, which
# produced three violations with no correct way to close them: moving the file
# would break four call sites, and creating three empty boards is appeasing the
# checker rather than fixing anything.
#
# The rule that separates the two: require the boards only where the folder
# BEHAVES like a methodology — it holds at least one dated run folder, or at least
# one board already. A folder with neither is data.
#
# Invariants:
#   1. A data-only folder raises no missing-board violation.
#   2. A folder holding a dated run still requires all three boards.
#   3. A folder holding one board still requires the other two (a half-built
#      methodology must not be reclassified as data by deleting a file).
set -euo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATE="$SKILL/scripts/validate-audit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

AUD="$TMP/.context/audits"
run() { "$VALIDATE" "$AUD" >"$TMP/out" 2>&1 || true; }
missing_boards() { grep -c 'audit-methodology-missing-board' "$TMP/out" || true; }

# ---- 1. data-only folder: no boards demanded ------------------------------
rm -rf "$AUD"; mkdir -p "$AUD/test-coverage"
printf '{"modules": []}\n' > "$AUD/test-coverage/module-map.json"
printf '<!-- GENERATED -->\n# Coverage matrix\n' > "$AUD/test-coverage/coverage-matrix.md"
printf '{"path": "a.py", "score": 1}\n' > "$AUD/test-coverage/defect-prone.jsonl"
run
[ "$(missing_boards)" = "0" ] \
  || err "data-only folder demanded methodology boards: $(grep 'missing-board' "$TMP/out")"

# ---- 2. a dated run makes it a methodology --------------------------------
rm -rf "$AUD"; mkdir -p "$AUD/ux/2026-08-18-a-run"
printf -- '---\ntitle: run\n---\n# run\n' > "$AUD/ux/2026-08-18-a-run/index.md"
run
[ "$(missing_boards)" = "3" ] \
  || err "folder with a dated run: expected 3 missing boards, got $(missing_boards)"

# ---- 3. one board present still requires the other two --------------------
rm -rf "$AUD"; mkdir -p "$AUD/ux"
printf -- '# UX methodology\n' > "$AUD/ux/00-methodology.md"
run
[ "$(missing_boards)" = "2" ] \
  || err "folder with one board: expected 2 missing boards, got $(missing_boards)"

[ "$fail" -eq 0 ] || exit 1
echo "OK — a folder under audits/ needs boards only when it behaves like a methodology"
