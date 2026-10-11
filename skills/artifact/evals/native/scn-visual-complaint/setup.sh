#!/bin/bash
set -e
# Built from a real scenario's SHAPE (LOOP-012 campaign 2); the content is neutral.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$REPO/skills/artifact/scripts"
printf '# Project\n\nSmall shop admin: orders, customers, a Django back office.\n' > CLAUDE.md
mkdir -p .context/reports
# Suppress the style-profile offer: these cases measure the page, not onboarding.
touch .context/.aidex-artifact-style-offered

cat > .context/reports/2026-10-09-modes.spec.md <<'SPEC'
::: masthead {title="Modos de uso del panel" eyebrow="Informe" byline="9 oct 2026" lang="es"}
Qué rol usa cada modo y desde qué dispositivo.
:::

::: section {#S1 heading="Comparativa de modos"}
| Modo | Rol principal | Dispositivo habitual | Acceso a pedidos | Acceso a clientes | Exportación de datos | Notificaciones por correo |
|---|---|---|---|---|---|---|
| Lectura | Soporte | Portátil | Solo ver | Solo ver | No | Resumen semanal |
| Edición | Operaciones | Portátil | Ver y editar | Ver y editar | CSV | Cada cambio |
| Administración | Responsable de tienda | Portátil y móvil | Todo | Todo | CSV y PDF | Cada cambio y alertas |
:::
SPEC
( cd .context/reports && python3 "$SCRIPTS/spec_build.py" 2026-10-09-modes.spec.md -o 2026-10-09-modes.html --check >/dev/null )
# The page predates the spec route and the kit's table wrapper: only its HTML exists,
# the table sits in a plain div (the layout contract names this), and no sidecar remains.
rm -f .context/reports/2026-10-09-modes.spec.md
rm -rf .context/reports/.aidex-artifact-prev
sed -i '' '1{/^<!-- GENERATED from /d;}' .context/reports/2026-10-09-modes.html
sed -i '' 's|<div class="tw"><table>|<div><table>|' .context/reports/2026-10-09-modes.html
