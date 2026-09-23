#!/usr/bin/env bash
# gallery-items.sh — turn a gallery rows JSON into one consult-group of review
# items. Thin wrapper; the logic lives in dash/gallery_items.py.
#
# Usage:
#   gallery-items.sh <rows.json> --root <abs repo root> \
#       --group-id <id> --group-title <title> [--lang es|en]
#
# The project owns the matrix and emits the rows (dashboard_template's
# `_scripts/gallery_board.py --rows-json <gallery>`); this turns them into
# `consult-item consult-gallery` sections the kit's composer and
# check-artifact.sh already understand. Output goes to stdout: paste it into the
# page's body sidecar (or hand it to artifact-item.sh put) and wrap as usual.
#
# Output is deterministic. Exit 2 with one plain line on a malformed document.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 "$SCRIPT_DIR/dash/gallery_items.py" "$@"
