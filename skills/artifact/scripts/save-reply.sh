#!/usr/bin/env bash
# save-reply.sh — save a consultation reply BEFORE the next round is built
# (unreadable-question.md § BL-475). Thin wrapper; logic lives in
# dash/save_reply.py.
#
# Run this FIRST on receiving a paste (or a chat reply — save that text the
# same way, there is no bypass), before briefing the rewrite. It writes the
# paste verbatim (less a leading UTF-8 BOM) to
# .aidex-artifact-prev/<stem>.reply.md and snapshots the page as the reader saw
# it to .aidex-artifact-prev/<stem>.answered.html, then
# prints the DUTIES the next round owes — paste that list into the brief.
#
# Usage:
#   save-reply.sh <page.html> <reply-file>
#   save-reply.sh <page.html> -     # or omit the reply arg: read stdin
#   pbpaste | save-reply.sh <page.html>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 "$SCRIPT_DIR/dash/save_reply.py" "$@"
