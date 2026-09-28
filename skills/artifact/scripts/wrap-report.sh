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
#   wrap-report.sh --title "<title>" --lang en --in report.md --out report.html
#
# A DELEGATED build (an agent writing the page for someone else) adds --building to
# every wrap and ends with one --done:
#   wrap-report.sh --building --title "<title>" --in body.html --out out.html
#   wrap-report.sh --done --out out.html
# Between the two, out.html carries a lock at .aidex-artifact-prev/out.html.building and
# artifact-open-once.sh refuses to open it: an agent writes its --out path several times
# mid-run and an intermediate wrap PASSES the contract, so neither the file changing nor
# a green check means the build is over — only the hand-back does. --done wraps nothing,
# removes the lock and is safe to repeat. A lock nobody cleared is ignored after 20 min.
#
# An `--in` file ending in `.md` is rendered from markdown first (dash/md_body.py):
# the close-out case, where a run already wrote a durable report and only the page
# is missing. Content on stdin is always page markup — a pipe has no name to read
# the intent from. Every page follows the profile's language; only a
# `human-verification.*` page takes `--lang en` (D-04), and an explicit `--lang`
# that contradicts the profile anywhere else is refused (LOOP-006).
#
# For a `.md` input `--title` is also the fallback `<h1>`, used when the markdown
# carries no `# ` line of its own — `human-verification.md` is that shape, and
# without it the page opens with no heading at all and an empty rail.
#
# Prefer --out over a shell redirect: it writes the file AND runs check-artifact.sh on it,
# exiting non-zero if the contract fails. The verify is the step a real run drops first
# (skipped in 1 of 2 field probes), so it stops being a separate step you can forget.
# Redirecting to stdout still works and prints a NOTE saying the contract went unverified.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 "$SCRIPT_DIR/dash/wrap_report.py" "$@"
