#!/bin/bash
set -e
# Built from a real scenario's SHAPE (LOOP-012); the content is neutral.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$REPO/skills/artifact/scripts"
printf '# Project\n\nSmall shop admin: orders, customers, a Django back office.\n' > CLAUDE.md
mkdir -p .context/research .context/reports
# Suppress the style-profile offer: these cases measure the page, not onboarding.
touch .context/.aidex-artifact-style-offered

cat > .context/research/2026-10-09-task-costs.tsv <<'TSV'
task	usd	tokens	minutes
import catalogue	4.20	1810000	38
invoice template	1.10	420000	12
refund flow	6.80	2950000	61
search filters	2.40	990000	22
TSV
