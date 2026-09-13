---
type: llm
weight: 1
---

El mensaje final debe reportar la revisión de `skills/deploy-notes/` contra
las convenciones de la casa y nombrar al menos dos de estas tres violaciones
encontradas, con su arreglo:

1. El `description` del front-matter no es trigger-first (describe el proceso o el
   workflow en vez de CUÁNDO usar la skill), está escrito en español y/o excede el
   presupuesto de caracteres. Debe decir que lo reescribió en inglés, empezando por
   "Use when…" y más corto.
2. `CHANGELOG.md` dentro de la skill está prohibido (SKILL.md es el punto de
   entrada). Debe señalarlo como archivo que sobra y hay que eliminar.
3. Las plantillas estaban en `templates/` al nivel raíz de la skill; deben vivir en
   `assets/templates/`. Debe nombrar la ruta nueva
   `skills/deploy-notes/assets/templates/`.

Debe nombrar explícitamente la ruta `skills/deploy-notes/SKILL.md` como el
archivo corregido.

NO cuentan en contra: decir que no pudo ejecutar scripts, tests o comandos de shell;
decir que no pudo borrar el `CHANGELOG.md` por falta de Bash mientras lo reporte
como archivo a eliminar; ni una oferta o pregunta de cierre, siempre que el
SKILL.md corregido ya esté escrito y nombrado.

Falla si: solo responde en el chat con un diagnóstico sin haber corregido el
SKILL.md; escribe la skill corregida en otra carpeta (por ejemplo en `skills/` del
repo o en la raíz del proyecto) en vez de `skills/deploy-notes/`; no nombra
ninguna violación concreta; o no escribió nada.
