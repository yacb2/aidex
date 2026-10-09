#!/usr/bin/env bash
# artifact-item.sh — read or replace ONE unit of a page's body sidecar, without
# loading the page. Thin wrapper; the logic lives in dash/artifact_item.py.
#
# Usage:
#   artifact-item.sh list <page.html>            # the outline: id · kind · size · title
#   artifact-item.sh get  <page.html> <id>       # exactly that unit's source
#   artifact-item.sh put  <page.html> <id> <file># replace exactly that unit
#
# It reads and writes `.aidex-artifact-prev/<page>.html.body` (`.body.md` for a
# markdown source) — the sidecar the wrap keeps, which is the source of a page made
# by wrap-report.sh. A page built from a `<page>.spec.md` (spec_build.py) is the
# exception: the spec is its source, `put` refuses it and names the spec, and a
# put + wrap forced past that would be overwritten by the next spec rebuild. Edit
# the spec instead. It NEVER wraps: `put` prints the wrap-report.sh command to run
# next, and that command is what verifies the contract.
#
# `put` refuses an id that is missing or duplicated, and refuses a replacement whose
# outer element does not carry the same id: ids are assigned once and never
# renumbered (references/02-local-first-artifacts.md § 8.1). Everything outside the
# unit stays byte for byte as it was.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 "$SCRIPT_DIR/dash/artifact_item.py" "$@"
