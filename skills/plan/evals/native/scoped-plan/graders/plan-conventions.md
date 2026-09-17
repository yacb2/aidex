---
type: llm
weight: 1
---

Lo único que se juzga aquí es la SUSTANCIA del plan: que cubra la exportación a
Excel del informe mensual reutilizando `report_sections()` de
`src/reports/render.py`, con openpyxl, el endpoint
`GET /reports/<id>/export.xlsx` y el botón en la vista de detalle, y que recoja
el criterio de aceptación que dio el usuario (el .xlsx abre en Excel con una
hoja por sección y las mismas cifras que el PDF).

Pasa aunque el mensaje diga que no pudo ejecutar el reindexado, la validación u
otros scripts y pida al usuario correrlos.

Falla si el plan se redactó en el chat sin crear el archivo, si inventa
migraciones o cambios de modelo que el usuario descartó expresamente, o si el
agente se quedó preguntando sin escribir nada.

La ruta y el front-matter (incluido `mode: scoped`, el resultado del triage) NO
se juzgan aquí — los asserta `plan-structure` sobre el archivo. El contrato de
archivos, el `Out of scope` y la fase única los impone `validate.py`, no un
grader.
