#!/usr/bin/env bash
# gallery-reply.sh — turn a pasted consultation reply into JSON: gallery rows
# with verdict, notes and region marks; every other item untouched under
# `other`. Thin wrapper; the logic lives in dash/gallery_reply.py.
#
# Usage:
#   gallery-reply.sh [--rows <rows.json>]... [--tiles "<t1> <t2> ..."] [<reply.md>]   # no file or `-`: stdin
#   --rows: the rows document the page was built from; REQUIRED when the reply holds an
#           alternatives or states row (its labels are the spec's), repeat once per gallery
#   --tiles: the block's data-tiles; a mark on any other tile is refused
#            (a states row's marks name its own states instead)
#   gallery-reply.sh --help
#
# The input is exactly the block the page's copy button produced: text added
# after it cannot be told apart from a row's notes.
#
# The reverse of gallery-items.sh: that one writes the rows the composer pastes,
# this one reads the paste back. Output goes to stdout.
#
# Exit 2 with one plain line naming the input line on a malformed mark, text
# after a row's marks, or two answers in one row.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 "$SCRIPT_DIR/dash/gallery_reply.py" "$@"
