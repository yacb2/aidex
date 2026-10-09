#!/bin/bash
set -e
# Built from a real scenario's SHAPE (LOOP-012); the content is neutral.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$REPO/skills/artifact/scripts"
printf '# Project\n\nSmall shop admin: orders, customers, a Django back office.\n' > CLAUDE.md
mkdir -p .context/research .context/reports
# Suppress the style-profile offer: these cases measure the page, not onboarding.
touch .context/.aidex-artifact-style-offered

mkdir -p .context/research/2026-10-09-order-list
cat > .context/research/2026-10-09-order-list.md <<'MDOC'
---
title: Order list
status: open
created: 2026-10-09
updated: 2026-10-09
---

# Order list

The operator works the order list all day. Today it is sorted by creation date, so urgent
orders are found by hand, and closed orders stay in the list and fill half the screen.
Round 1 of the consultation is `.context/research/2026-10-09-order-list/consulta.html`.
MDOC
cat > .context/research/2026-10-09-order-list/consulta.spec.md <<'SPEC'
::: masthead {title="Listado de pedidos" eyebrow="Consulta · ronda 1" byline="9 oct 2026" lang="es" visual="none: dos decisiones de orden y visibilidad, sin pantalla nueva"}
El operador trabaja el listado de pedidos todo el día; dos decisiones cambian lo que ve.
:::

::: group {#G1 title="El listado de pedidos"}
Hoy el listado sale por fecha de alta y conserva los pedidos cerrados.

::: item {#Q1 title="Orden del listado"}
Hoy el listado de pedidos sale por fecha de alta y el operador busca a mano los urgentes. ¿Cómo se ordena el listado?

- Por urgencia primero {recommended}
- Por fecha de alta
:::

::: item {#Q2 title="Pedidos cerrados"}
Los pedidos cerrados siguen en el listado y ocupan la mitad de la pantalla. ¿Qué pasa con los pedidos cerrados?

- Se ocultan a los 7 días {recommended}
- Se quedan siempre visibles
:::
:::
SPEC
( cd .context/research/2026-10-09-order-list && python3 "$SCRIPTS/spec_build.py" consulta.spec.md -o consulta.html --check >/dev/null )
