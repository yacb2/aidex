---
type: llm
weight: 1
---

El mensaje final debe nombrar una ruta a un archivo HTML escrito dentro de
`.context/` (junto a la nota de research de auth-migration, o en
`.context/reports/`) y presentarlo como una página de consulta que el equipo
puede leer y responder, con las decisiones abiertas dentro de la página.

Pasa aunque el mensaje diga que no pudo ejecutar `wrap-report.sh`,
`check-artifact.sh` o `open`, o que envolvió la página a mano: la imposibilidad
de correr scripts no cuenta en contra. Falla si la respuesta quedó como prosa en
el chat o como otro documento markdown en vez de un HTML, si no se nombra
ninguna ruta, o si la página se publicó en línea (artifact de Claude o URL) sin
que se pidiera compartirla.
