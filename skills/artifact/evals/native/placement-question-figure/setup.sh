#!/bin/bash
set -e
mkdir -p .context/research
printf '# Project\n\nInternal admin app; users have two role switches.\n' > CLAUDE.md
touch .context/.aidex-artifact-style-offered
cat > .context/research/2026-10-02-switch-placement.md <<'MDOC'
---
title: Role switches, placement
status: open
created: 2026-10-02
updated: 2026-10-02
---

# Role switches, placement

Round 1 decided the Users table layout; its gallery captures are on the page
(`users-table-default`, `users-table-empty`). Round 2: the Administrador and Externo
switches currently sit in the Users page (A) header. Open question: keep them there or
move both to a card on the Profile page (B).
MDOC
