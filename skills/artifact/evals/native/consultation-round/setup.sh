#!/bin/bash
set -e
mkdir -p .context/research
printf '# Project\n\nPublic pricing API; a Django service behind a CDN.\n' > CLAUDE.md
# Suppress the style-profile offer: this case measures the consultation contract, not onboarding.
touch .context/.aidex-artifact-style-offered
cat > .context/research/2026-10-09-price-cache.md <<'MDOC'
---
title: Price endpoint cache
status: open
created: 2026-10-09
updated: 2026-10-09
---

# Price endpoint cache

`GET /prices` takes 820 ms at p95 and serves 40 requests per second; prices change about
twelve times a day, always through the admin, and a stale price shown for more than five
minutes has cost two refunds this quarter.

## Open decisions

1. **Cache lifetime.** Situation: the endpoint recomputes every price on every call. A 60 s
   TTL cuts load about 98% and bounds staleness at one minute; a 1 h TTL cuts it a little
   more but can show a price an hour old. Recommended: 60 s, because staleness past five
   minutes has a measured cost.
2. **Invalidation on admin save.** Situation: the admin save is the only writer. Purging
   the cache key on save makes a new price visible at once and costs one signal handler;
   relying on the TTL alone costs nothing but leaves up to one TTL of staleness.
   Recommended: purge on save.
3. **Where the cache lives.** Situation: the service runs four workers on two hosts. Redis
   is already deployed for sessions and gives one shared cache; an in-process cache needs
   nothing new but keeps eight copies that expire at different moments, so two requests
   can see two prices. Recommended: Redis.
MDOC
