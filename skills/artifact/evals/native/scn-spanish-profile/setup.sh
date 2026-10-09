#!/bin/bash
set -e
# Built from a real scenario's SHAPE (LOOP-012); the content is neutral.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$REPO/skills/artifact/scripts"
printf '# Project\n\nSmall shop admin: orders, customers, a Django back office.\n' > CLAUDE.md
mkdir -p .context/research .context/reports

mkdir -p .context/profiles
sed 's/^- language: en$/- language: es/' "$REPO/skills/artifact/assets/templates/artifact.md.template" > .context/profiles/artifact.md
grep -q '^- language: es$' .context/profiles/artifact.md
touch .context/.aidex-artifact-style-offered
cat > .context/research/2026-10-09-incidents.md <<'MDOC'
---
title: September incidents
status: done
created: 2026-10-09
updated: 2026-10-09
---

# September incidents

1. **Checkout down, 2026-09-04, 42 min.** A payment provider certificate expired; renewed by
   hand. Follow-up: alert 14 days before expiry.
2. **Duplicate invoices, 2026-09-17, 310 invoices.** A retried job ran twice; invoices were
   voided and re-sent. Follow-up: idempotency key on the invoice job.
3. **Slow search, 2026-09-26, 3 h.** A missing index after a migration; p95 went from 0.3 s
   to 4.1 s. Follow-up: migration check for dropped indexes.
MDOC
