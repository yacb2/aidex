---
type: llm
weight: 1
---

El mensaje final debe informar que `.context/` quedó creado con sus carpetas
(backlog, plans, decisions, research, references, requests) y sugerir, sin
escribirlo por su cuenta, un bloque para CLAUDE.md. Pasa aunque diga que algún
paso opcional se omitió. Falla si crea `.context/` a mano archivo por archivo
sin usar el script de inicialización, o si solo explica qué es aidex sin
crear nada.
