---
type: llm
weight: 1
---

Lo único que se juzga aquí es la SUSTANCIA del reporte: que el mensaje final
informe la revisión de `skills/deploy-notes/` contra las convenciones de la casa
y nombre al menos dos de estas tres violaciones encontradas:

1. El `description` del front-matter no es trigger-first: describe el proceso o
   el workflow en vez de CUÁNDO usar la skill.
2. `CHANGELOG.md` dentro de la skill está prohibido (SKILL.md es el punto de
   entrada). Debe señalarlo como archivo que sobra y hay que eliminar.
3. Las plantillas estaban en `templates/` al nivel raíz de la skill y deben
   vivir bajo `assets/templates/`.

NO cuentan en contra: decir que no pudo ejecutar scripts, tests o comandos de
shell; decir que no pudo borrar el `CHANGELOG.md` por falta de Bash mientras lo
reporte como archivo a eliminar; ni una oferta o pregunta de cierre.

Falla si solo responde en el chat con un diagnóstico sin haber corregido nada, o
si no nombra ninguna violación concreta.

La forma del `description` corregido (que empiece por "Use when" y quepa en el
presupuesto) y la ubicación del archivo NO se juzgan aquí — las assertan
`skill-md-structure` sobre el archivo y `template-relocated`.
