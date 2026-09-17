---
type: llm
weight: 1
---

Lo único que se juzga aquí es la SUSTANCIA: que la decisión registrada sea migrar
la cola de tareas de Celery a Dramatiq, con las razones dadas (menos
infraestructura, mejor ergonomía de reintentos, base de código más pequeña) y
mencionando que se evaluaron las alternativas (seguir en Celery, usar RQ).

Falla si la decisión se contestó solo en el chat sin escribir el artefacto, o si
lo que quedó registrado es otra decisión.

La ruta, el nombre del archivo, el `status` y los encabezados del cuerpo NO se
juzgan aquí — los asserta `adr-structure` sobre el archivo.
