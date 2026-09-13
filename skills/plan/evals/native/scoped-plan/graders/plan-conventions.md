---
type: llm
weight: 1
---

El mensaje final debe decir que el plan quedó escrito en `.context/plans/` y
describirlo como un plan con fases y criterios de aceptación. Pasa aunque el
mensaje diga que no pudo ejecutar el reindexado, la validación u otros scripts y
pida al usuario correrlos: la imposibilidad de ejecutar scripts no cuenta en
contra. Falla si el plan se redactó en el chat sin crear el archivo, si va a
otra carpeta, o si el agente se quedó preguntando sin escribir nada.

El nombre del archivo debe empezar por una fecha ISO `YYYY-MM-DD`.
