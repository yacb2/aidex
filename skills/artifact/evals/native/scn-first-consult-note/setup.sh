#!/bin/bash
set -e
# Built from a real scenario's SHAPE (LOOP-012); the content is neutral.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$REPO/skills/artifact/scripts"
printf '# Project\n\nSmall shop admin: orders, customers, a Django back office.\n' > CLAUDE.md
mkdir -p .context/research .context/reports
# Suppress the style-profile offer: these cases measure the page, not onboarding.
touch .context/.aidex-artifact-style-offered

cat > .context/research/2026-10-09-order-digest.md <<'MDOC'
---
title: Daily order digest email
status: open
created: 2026-10-09
updated: 2026-10-09
---

# Daily order digest email

Shop owners get one email per order today, about 60 a day, and most of them have muted
the sender. A daily digest is planned; three things are still open.

## Open decisions

1. **When it is sent.** At 08:00 local time the owner reads it before opening the shop;
   at 20:00 it covers the whole day but arrives after closing. Recommended: 08:00.
2. **What it lists.** Every order of the day (about 60 lines), or only orders that need an
   action (refunds, failed payments, about 5 a day). Recommended: only orders that need an
   action, with a count of the rest.
3. **Whether per-order emails stay.** Keeping them as an opt-in costs nothing new; removing
   them simplifies the settings page but breaks two shops that forward them to a printer.
   Recommended: keep them as an opt-in.
MDOC
