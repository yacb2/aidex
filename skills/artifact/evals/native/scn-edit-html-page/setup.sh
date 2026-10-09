#!/bin/bash
set -e
# Built from a real scenario's SHAPE (LOOP-012); the content is neutral.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$REPO/skills/artifact/scripts"
printf '# Project\n\nSmall shop admin: orders, customers, a Django back office.\n' > CLAUDE.md
mkdir -p .context/research .context/reports
# Suppress the style-profile offer: these cases measure the page, not onboarding.
touch .context/.aidex-artifact-style-offered

cat > .context/reports/2026-10-09-status.spec.md <<'SPEC'
::: masthead {title="Estado del proyecto" eyebrow="Informe" byline="9 oct 2026" lang="es"}
Dónde está el back office de la tienda esta semana.
:::

::: section {#S1 heading="Hecho esta semana"}
- Importación del catálogo en producción.
- Plantilla de factura nueva.
:::

::: section {#S2 heading="Siguiente"}
- Flujo de devoluciones.
- Filtros de búsqueda.
:::
SPEC
( cd .context/reports && python3 "$SCRIPTS/spec_build.py" 2026-10-09-status.spec.md -o 2026-10-09-status.html --check >/dev/null )
# The page predates the spec route: only its HTML exists.
rm -f .context/reports/2026-10-09-status.spec.md
