---
type: llm
weight: 1
---

El mensaje final debe decir que la decisión quedó registrada como un ADR en
`.context/decisions/` con estado `accepted`. Falla si la decisión se contestó
solo en el chat sin crear el artefacto, o si va a otra carpeta.

El nombre del archivo debe empezar por una fecha ISO `YYYY-MM-DD`.
