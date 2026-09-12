---
type: llm
weight: 1
---

El mensaje final debe decir que la referencia quedó escrita bajo
`.context/references/` y describirla como documentación evergreen de cómo
funciona la autenticación por API key (no un plan, no una decisión, no una
investigación).

Falla si la referencia se redactó solo en el chat sin crear el archivo, si va a
otra carpeta, o si el agente se quedó preguntando sin escribir nada.

No exijas que el mensaje recite los campos del front-matter ni el nombre exacto
del archivo.
