---
type: llm
weight: 1
---

Lo único que se juzga aquí es la SUSTANCIA del diseño del loop:

1. El objetivo es arreglar `src/cart.py` hasta que la suite pase.
2. La condición de parada es verificable por máquina — `./run_tests.sh` en
   verde / exit 0 — con el tope de 15 iteraciones que pidió el usuario.
3. El guardrail de no tocar `tests/` quedó recogido.

No cuenta en contra que el mensaje diga que no pudo ejecutar scripts, tests o el
validador, ni que cierre con un ofrecimiento o una pregunta. Tampoco cuenta en
contra que el loop no se haya ejecutado: el usuario pidió expresamente no
ejecutarlo.

Falla si la respuesta se queda en el chat sin escribir ningún archivo, si no se
nombra ninguna condición de parada verificable, o si lo diseñado no es un loop
sino un plan de trabajo por fases.

La ruta, el front-matter (incluido que `engine` quede resuelto y no en
`undecided`) y los encabezados del spec NO se juzgan aquí — los asserta
`loop-structure` sobre el archivo.
