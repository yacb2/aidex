---
type: llm
weight: 1
---

El mensaje final debe indicar que se creó un ADR en `.context/decisions/` con
nombre `YYYY-MM-DD-<slug>.md` (fecha ISO real, slug kebab-case) y front-matter
con status `accepted`. Falla si el archivo va a otra carpeta, si el nombre no
lleva fecha ISO, o si el status no es del enum ADR (accepted/superseded/dropped).
