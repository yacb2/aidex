---
type: llm
weight: 1
---

Lo único que se juzga aquí es la SUSTANCIA: que el pedido capturado sea exportar
a Excel los informes mensuales, recogiendo el motivo (finanzas los reconcilia a
mano) y el plazo (antes del cierre de trimestre).

Falla si el pedido se contestó solo en el chat sin escribir el artefacto, o si lo
que quedó capturado es otro pedido.

La ruta, el nombre del archivo y los encabezados del cuerpo NO se juzgan aquí —
los asserta `request-structure` sobre el archivo.
