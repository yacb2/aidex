---
type: llm
weight: 1
---

Lo único que se juzga aquí es la SUSTANCIA del diseño de la orquestación:

1. El fan-out reparte los cuatro módulos (`src/auth.py`, `src/payments.py`,
   `src/notifications.py`, `src/reports.py`) sobre las dos dimensiones pedidas,
   corrección y seguridad.
2. Cada agente tiene modelo y esfuerzo asignados concretamente, no "el que
   corresponda".
3. Hay una regla de aceptación que dice qué debe cumplir la salida de cada
   agente para darse por buena.

Pasa si al menos dos de las tres quedaron cubiertas.

No cuenta en contra que el mensaje diga que no pudo ejecutar scripts o el
validador, ni que cierre con un ofrecimiento. Tampoco cuenta en contra que la
orquestación no se haya lanzado: el usuario pidió expresamente no lanzarla.

Falla si la respuesta se queda en el chat sin escribir ningún archivo, o si lo
diseñado es algo que se repite hasta que pasa un check (un loop) en vez de una
sola pasada en paralelo.

La ruta, el front-matter (incluido que `shape` quede resuelto y no en
`undecided`) y los encabezados del spec NO se juzgan aquí — los asserta
`workflow-structure` sobre el archivo.
