#!/bin/bash
set -e
mkdir -p .context/research
printf '# Project\n\nSmall SaaS; cloud spend is reviewed monthly.\n' > CLAUDE.md
# Suppress the style-profile offer: this case measures the quality loop, not onboarding.
touch .context/.aidex-artifact-style-offered
cat > .context/research/2026-09-20-cloud-spend.md <<'MDOC'
---
title: Cloud spend, 2026
status: open
created: 2026-09-20
updated: 2026-09-20
---

# Cloud spend, 2026

Monthly invoice total, USD.

| Month | Spend |
|---|---|
| January | 1840 |
| February | 1795 |
| March | 1910 |
| April | 1880 |
| May | 4620 |
| June | 2050 |

May includes a one-off data migration that ran for eleven days on on-demand instances.
MDOC
