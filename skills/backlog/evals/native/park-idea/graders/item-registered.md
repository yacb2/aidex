---
type: llm
weight: 1
---

Lo único que se juzga aquí es la SUSTANCIA: que lo registrado sea la idea de
exportar las notas a CSV desde `src/export.py`, y que NO se haya implementado la
exportación.

Pasa aunque el mensaje mencione que algún script no pudo ejecutarse. Falla si el
agente escribió `export_csv` o tocó `src/export.py`, o si solo describió la idea
en el chat sin registrar nada.

El id, el front-matter y los encabezados del ítem NO se juzgan aquí — los
asserta `item-structure` sobre el archivo.
