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

Round 1 decided the Users table layout; its consultation spec is
`.context/research/2026-10-02-switch-placement/consulta.spec.md`. Round 2: the
Administrador and Externo switches currently sit in the Users page (A) header. Open
question: keep them there or move both to a card on the Profile page (B).
MDOC
mkdir -p .context/research/2026-10-02-switch-placement
cat > .context/research/2026-10-02-switch-placement/consulta.spec.md <<'SPEC'
::: masthead {title="Switches de rol: ubicación" eyebrow="Consulta · ronda 1" byline="2 oct 2026" lang="es" visual="none: ronda 1 solo decide columnas de una tabla"}
Ronda 1 cerró la tabla de Usuarios.
:::

::: group {#G1 title="Tabla de Usuarios"}
La tabla de Usuarios ya tiene su diseño.

::: item {#Q1 title="Columnas por defecto" decided=yes proposal=yes}
¿Qué columnas muestra la tabla?

- Nombre, correo y rol {chosen}
- Solo nombre y correo
:::
:::

::: notes {title="Notas generales"}
:::
SPEC
