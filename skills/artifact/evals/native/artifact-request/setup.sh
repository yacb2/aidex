#!/bin/bash
set -e
mkdir -p .context/research .context/decisions
printf '# Project\n\nDjango + Vue app. Sessions are cookie-based today; the auth rewrite is in flight.\n' > CLAUDE.md
# Suppress the style-profile offer: this case measures the artifact flow, not onboarding.
touch .context/.aidex-artifact-style-offered
cat > .context/research/2026-09-05-auth-migration-options.md <<'MDOC'
---
title: Auth migration options
status: open
created: 2026-09-05
updated: 2026-09-05
---

# Auth migration options

The current stack signs users in with Django's session cookie and a server-rendered
login view. Three routes were costed.

## Option A — keep sessions, add a refresh endpoint

- Migration cost: 3 days. No mobile client support.
- Blast radius: `accounts/views.py`, `accounts/middleware.py`.
- Open question: does the SPA need cross-subdomain cookies?

## Option B — JWT in the SPA, sessions kept for the admin

- Migration cost: 9 days. Mobile works on day one.
- Blast radius: every DRF viewset, the Vue router guards, the logout flow.
- Open question: where do refresh tokens live, and who revokes them?

## Option C — external IdP (Auth0 / Keycloak)

- Migration cost: 6 days plus an operations owner we do not have.
- Blast radius: the whole login surface, plus a new runtime dependency.
- Open question: is the recurring cost approved?

## Undecided

1. Which option ships first.
2. Whether the admin keeps session auth after the cut-over.
3. Who owns token revocation.
4. Whether the mobile client is in scope for this quarter.
