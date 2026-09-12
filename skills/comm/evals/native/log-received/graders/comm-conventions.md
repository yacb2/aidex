---
type: llm
weight: 1
---

El mensaje final debe decir que el correo quedó registrado como una comunicación
dentro de `.context/communications/received/`, e identificar de qué correo se
trata (el mensaje de Ana Robles sobre los ajustes al portal).

Falla si el correo solo se resumió o se contestó en el chat sin crear el
artefacto, si la comunicación se guardó en otra carpeta (por ejemplo `sent/`,
`meetings/`, `requests/` o fuera de `.context/`), o si el agente se quedó
preguntando en lugar de registrarlo.

Lo único que se juzga es dónde quedó la comunicación: que además haya creado
requests, items de backlog o referencias cruzadas junto con ella no es motivo de
falla. Tampoco se exige que el mensaje recite los campos del front-matter.
