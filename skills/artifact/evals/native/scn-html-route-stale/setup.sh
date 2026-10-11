#!/bin/bash
set -e
# Built from a real scenario's SHAPE (LOOP-012 campaign 2); the content is neutral.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$REPO/skills/artifact/scripts"
printf '# Project\n\nSmall shop admin: orders, customers, a Django back office.\n' > CLAUDE.md
mkdir -p .context/reports
# Suppress the style-profile offer: these cases measure the page, not onboarding.
touch .context/.aidex-artifact-style-offered

cat > .context/reports/2026-10-09-sprint.spec.md <<'SPEC'
::: masthead {title="Estado del sprint" eyebrow="Informe" byline="9 oct 2026" lang="es"}
Cómo va el trabajo del back office de la tienda.
:::

::: section {#S1 heading="Cifras"}
| Indicador | Valor |
|---|---|
| Tareas hechas | 12 |
| Tareas pendientes | 7 |
| Bloqueadas | 2 |
:::

::: section {#S2 heading="Siguiente"}
- Flujo de devoluciones.
- Filtros de búsqueda.
:::
SPEC
( cd .context/reports && python3 "$SCRIPTS/spec_build.py" 2026-10-09-sprint.spec.md -o 2026-10-09-sprint.html --check >/dev/null )
# The page predates the spec route: only its HTML exists.
rm -f .context/reports/2026-10-09-sprint.spec.md
# A page from before the spec route carries no spec-built marker (F11).
sed -i '' '1{/^<!-- GENERATED from /d;}' .context/reports/2026-10-09-sprint.html \
  .context/reports/.aidex-artifact-prev/2026-10-09-sprint.html
