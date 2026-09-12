---
type: llm
weight: 1
---

El mensaje final debe decir que el plan quedó escrito en `.context/plans/` y
describirlo como un plan con fases y criterios de aceptación. Falla si el plan se
redactó en el chat sin crear el archivo, si va a otra carpeta, o si el agente se
quedó preguntando sin escribir nada.

El nombre del archivo debe empezar por una fecha ISO `YYYY-MM-DD`.
