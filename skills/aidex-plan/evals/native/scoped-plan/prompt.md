---
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

Quiero un plan para añadir exportación a Excel de los informes mensuales.
Ya está todo definido, no hace falta que me preguntes nada:

- Alcance: solo el informe mensual, reutilizando `report_sections()` de `src/reports/render.py`.
- Librería: openpyxl.
- Entrega: un endpoint nuevo `GET /reports/<id>/export.xlsx` y un botón en la
  vista de detalle del informe.
- Criterio de aceptación: el .xlsx abre en Excel con una hoja por sección y las
  mismas cifras que el PDF.
- No hay migraciones ni cambios de modelo.

Escribe el plan.
