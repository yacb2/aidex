#!/bin/bash
set -e
# Built from a real scenario's SHAPE (LOOP-012 campaign 2); the content is neutral.
printf '# Project\n\nSmall shop admin: orders, customers, a Django back office.\n' > CLAUDE.md
mkdir -p .context/research .context/reports
# Suppress the style-profile offer: these cases measure the page, not onboarding.
touch .context/.aidex-artifact-style-offered
cat > .context/research/2026-10-09-order-flow.md <<'MDOC'
# Ciclo de vida de un pedido

Un pedido pasa por cinco estados, siempre en este orden:

1. Creado: el cliente confirma el carrito.
2. Pagado: la pasarela de pago confirma el cobro.
3. Preparado: el almacén reúne los artículos.
4. Enviado: el transportista recoge el paquete.
5. Entregado: el cliente firma la recepción.

Quién actúa: el cliente en los estados 1 y 2, el almacén en el 3, el transportista en el 4 y el 5.
Un pedido solo avanza un estado cada vez y nunca retrocede.
MDOC
