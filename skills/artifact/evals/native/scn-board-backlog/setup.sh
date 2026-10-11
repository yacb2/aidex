#!/bin/bash
set -e
# Built from a real scenario's SHAPE (LOOP-012 campaign 2); the content is neutral.
printf '# Project\n\nSmall shop admin: orders, customers, a Django back office.\n' > CLAUDE.md
mkdir -p .context/backlog
# Suppress the style-profile offer: these cases measure the page, not onboarding.
touch .context/.aidex-artifact-style-offered
n=1
while IFS='|' read -r st pr ty ti es; do
  printf -- '---\nid: BL-%03d\ntitle: %s\nstatus: %s\npriority: %s\ntype: %s\nestimate: %s\n---\n\n# %s\n\nDetalle del elemento.\n' \
    "$n" "$ti" "$st" "$pr" "$ty" "$es" "$ti" > ".context/backlog/BL-$(printf '%03d' $n)-item.md"
  n=$((n+1))
done <<'ROWS'
open|P1|bug|Corregir el total del carrito|S
doing|P2|feature|Exportar pedidos a CSV|M
open|P3|chore|Actualizar dependencias|S
open|P2|feature|Buscador de clientes|L
done|P2|feature|Filtro por estado|S
ROWS
