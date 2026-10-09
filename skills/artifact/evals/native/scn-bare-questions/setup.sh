#!/bin/bash
set -e
# Built from a real scenario's SHAPE (LOOP-012); the content is neutral.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$REPO/skills/artifact/scripts"
printf '# Project\n\nSmall shop admin: orders, customers, a Django back office.\n' > CLAUDE.md
mkdir -p .context/research .context/reports
# Suppress the style-profile offer: these cases measure the page, not onboarding.
touch .context/.aidex-artifact-style-offered

cat > .context/research/2026-10-09-search-cache.md <<'MDOC'
---
title: Product search cache
status: open
created: 2026-10-09
updated: 2026-10-09
---

# Product search cache

Product search takes 1.4 s at p95 and the catalogue changes about twice a day, through a
nightly import and occasional manual edits in the admin. The service runs three workers on
one host. Redis is already deployed for sessions. A 60 s TTL bounds a stale result at one
minute; a 1 h TTL saves a little more load but a price edited in the admin can show the old
value for up to an hour, which support says customers notice.
MDOC
