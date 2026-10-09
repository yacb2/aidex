#!/usr/bin/env bash
# Reference size gate.
#
# The rule has one owner: skill-conventions.md § Reference File Organization (the
# "48,000 bytes" sentence). This script enforces that sentence and restates
# nothing; read the canon for why. Zero files checked under ROOT is itself a failure.
#
# Scope: skills/*/references/**/*.md (same walk as test_reference_toc.sh).
#
# Usage: bash skills/conventions/scripts/test_reference_size.sh [ROOT]
#   ROOT defaults to the repo root this script sits in. Exit 1 on any failing file.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="${1:-$(cd "$SCRIPT_DIR/../../.." && pwd -P)}"

python3 - "$ROOT" <<'PY'
import os, sys

CEILING = 48000
root = os.path.realpath(sys.argv[1])
checked = failing = 0
for d, _, fs in sorted(os.walk(os.path.join(root, "skills"))):
    parts = os.path.relpath(d, root).split(os.sep)
    if len(parts) < 3 or parts[2] != "references":
        continue
    for f in sorted(fs):
        if not f.endswith(".md"):
            continue
        p = os.path.join(d, f)
        checked += 1
        size = os.path.getsize(p)
        if size > CEILING:
            failing += 1
            print(f"FAIL {os.path.relpath(p, root)}: {size} bytes > {CEILING} "
                  "(a whole-file Read cuts near 64k chars, silently)")
if checked == 0:
    print(f"no reference files found under {root}")
    failing = 1
print(f"reference-size: {checked} files checked, {failing} failing")
sys.exit(1 if failing else 0)
PY
