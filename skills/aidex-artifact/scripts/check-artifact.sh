#!/usr/bin/env bash
# check-artifact.sh — verify a local-first artifact honours the file contract
# the Artifact tool enforces for published pages. Run it before opening the
# file; it is the deterministic half of rules/artifacts-local-first.md.
#
# Thin wrapper; the contract lives in dash/check_artifact.py. It was 486 lines
# of bash wrapping five python3 heredocs, and the dominant defect class in its
# own history — prose satisfying a grep on behalf of a page that does not carry
# the rule — lives on exactly that surface, so the scans moved into one Python
# process that strips scripts, styles and comments once and fails closed
# in-process.
#
# Usage: check-artifact.sh <file.html> [...]
#        check-artifact.sh <new.html> --prev <previous.html>
# Exit 0 = every file passes. Exit 1 = at least one violation (each printed).
# Exit 2 = usage error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 "$SCRIPT_DIR/dash/check_artifact.py" "$@"
