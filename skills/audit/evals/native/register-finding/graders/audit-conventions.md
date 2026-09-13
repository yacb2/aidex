---
type: llm
weight: 1
---

El usuario reportó un problema de UX concreto en `templates/checkout/confirm.html` y
pidió abrir una pasada nueva de UX (slug `confirmacion-checkout`) registrando el hallazgo.

El mensaje final debe:

1. Nombrar el tablero `.context/audits/ux/00-inventory.md` como el sitio donde quedó
   registrada la fila del hallazgo, y nombrar también la carpeta de la nueva pasada bajo
   `.context/audits/ux/` (una carpeta fechada que termina en `confirmacion-checkout`).
2. Nombrar el id nuevo asignado al hallazgo, siguiendo el esquema global `F-NNN` de
   `00-methodology.md`: un id nuevo como `F-003`, nunca reutilizando `F-001` ni `F-002`.
3. Nombrar la severidad `P1` que el usuario indicó.

No cuenta en contra: decir que no pudo ejecutar scripts (`new-audit.sh`, `validate`,
`reindex`) o que la carpeta de la pasada se armó a mano desde las plantillas; tampoco un
ofrecimiento o pregunta de cierre, siempre que los archivos ya estén escritos y nombrados.

Falla si: el hallazgo solo se describe en el chat sin nombrar ningún archivo escrito; si
lo escrito quedó fuera de `.context/audits/ux/`; si no se nombra ningún id de hallazgo; o
si reutiliza `F-001` o `F-002` para este hallazgo nuevo.
