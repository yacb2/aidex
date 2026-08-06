#!/usr/bin/env bash
# wrap-report.sh — wrap ad-hoc report content in the document envelope the
# Artifact tool would have supplied at publish time (doctype, html lang, head
# with charset/viewport/title, minimal reset). Thin wrapper; logic lives in
# dash/wrap_report.py.
#
# Write page content the way `artifact-design` teaches — styles and markup, no
# doctype/html/head/body — then pipe it through here. A local artifact that
# skips this step lands as a headless fragment and renders in quirks mode.
#
# Usage:
#   wrap-report.sh --title "<title>" [--lang es] [--favicon "📊"] --out out.html < body.html
#   wrap-report.sh --title "<title>" --in body.html --out out.html
#
# Prefer --out over a shell redirect: it writes the file AND runs check-artifact.sh on it,
# exiting non-zero if the contract fails. The verify is the step a real run drops first
# (skipped in 1 of 2 field probes), so it stops being a separate step you can forget.
# Redirecting to stdout still works and prints a NOTE saying the contract went unverified.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 "$SCRIPT_DIR/dash/wrap_report.py" "$@"
