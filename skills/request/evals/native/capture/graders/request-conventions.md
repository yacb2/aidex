---
type: llm
weight: 1
---

El mensaje final debe decir que el pedido quedó capturado como un artefacto en
`.context/requests/`, e identificar de qué pedido se trata (exportar a Excel los
informes mensuales). Falla si el pedido se contestó solo en el chat sin crear el
artefacto, o si lo guardó en otra carpeta.

El nombre del archivo debe empezar por una fecha ISO `YYYY-MM-DD`.
