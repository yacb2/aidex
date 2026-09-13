---
type: llm
weight: 1
---

El mensaje final debe reportar la ejecución de la FASE 1 del plan
`.context/plans/2026-09-10-slug-de-exportacion/` y nada más. Pasa si cumple las
tres propiedades:

1. Nombra los archivos de la fase 1 como entregable: `src/text_utils.py` (con la
   función `slugify` agregada) y el test nuevo `tests/test_slugify.py`.
2. Dice que marcó los checkboxes de la fase 1 como hechos en el plan (en
   `01-slugify.md` y/o en el índice `00-index.md` del plan).
3. Deja explícito que la fase 2 (`src/export.py`) no se empezó y queda pendiente.

Frases como "no pude correr los tests", "no pude ejecutar
`python3 -m unittest`", "no pude hacer el commit" o "no pude correr el
code-review" NO cuentan en contra: en este entorno no hay shell. Tampoco cuenta
en contra una oferta o pregunta de cierre ("¿sigo con la fase 2?"), siempre que
los archivos ya estén escritos y nombrados.

Falla si: el `slugify` o el test se entregan solo como código en el chat sin
escribir los archivos; los archivos se escriben fuera de `src/` y `tests/`; el
plan no se actualiza; o si además ejecutó la fase 2 tocando `src/export.py`.
