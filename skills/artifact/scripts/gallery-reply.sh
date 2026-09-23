#!/usr/bin/env bash
# gallery-reply.sh — turn a pasted consultation reply into JSON: gallery rows
# with verdict, notes and region marks; every other item untouched under
# `other`. Thin wrapper; the logic lives in dash/gallery_reply.py.
#
# Usage:
#   gallery-reply.sh [<reply.md>]     # no argument or `-`: read stdin
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
