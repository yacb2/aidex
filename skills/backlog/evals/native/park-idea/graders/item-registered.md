---
type: llm
weight: 1
---

El mensaje final debe confirmar que la idea de exportar notas a CSV quedó
registrada como un ítem del backlog con un id `BL-NNN` (por ejemplo BL-002) en
`.context/backlog/`, sin implementar la exportación. Pasa aunque el mensaje
mencione que algún script no pudo ejecutarse, siempre que el ítem exista. Falla
si el mensaje implementa `export_csv`, o si solo describe la idea en el chat sin
nombrar un archivo o id de backlog creado.
