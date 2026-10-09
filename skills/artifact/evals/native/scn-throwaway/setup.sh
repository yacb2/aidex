#!/bin/bash
set -e
# Built from a real scenario's SHAPE (LOOP-012); the content is neutral.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$REPO/skills/artifact/scripts"
printf '# Project\n\nSmall shop admin: orders, customers, a Django back office.\n' > CLAUDE.md
mkdir -p .context/research .context/reports
