#!/bin/bash
set -e
mkdir -p .context/decisions .context/backlog .context/references
printf '# Project\n\nSmall Django + Vue app.\n' > CLAUDE.md
cat > .context/decisions/2026-11-01-invoice-pdfs-in-object-storage.md <<'A'
---
title: Invoice PDFs are stored in object storage
status: accepted
created: 2026-11-01
updated: 2026-11-01
---

## Context

Customers download their invoices as PDF. The files can be rendered on every
request, stored on the app server, or stored in object storage.

## Decision

Invoice PDFs are rendered once and stored in object storage; customers download
them through a signed link.

## Consequences

- No rendering on the download path.
- Storage cost grows with the number of invoices.
A
cat > .context/backlog/2026-11-02-bl-301-invoice-pdf-downloads.md <<'B'
---
title: Invoice PDF downloads
status: open
created: 2026-11-02
updated: 2026-11-02
---

# BL-301 Invoice PDF downloads

Implement the signed download link for stored invoice PDFs, as decided in the
2026-11-01 ADR.

## Open points

- Retention of stored PDFs: to be confirmed by Legal.
- Lifetime of the download link: to be confirmed by Legal.
B
