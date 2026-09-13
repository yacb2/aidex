---
type: llm
weight: 1
---

El mensaje final debe nombrar el archivo de loop-spec escrito bajo
`.context/loops/` (por ejemplo `.context/loops/2026-09-13-cart-tests-green.md`;
el nombre y la fecha pueden variar).

Además, el mensaje final debe dejar ver que la especificación cubre, al menos:

1. El objetivo del loop (arreglar `src/cart.py` hasta que la suite pase).
2. Una condición de parada verificable por máquina — `./run_tests.sh` en verde /
   exit 0 — junto con el tope de 15 iteraciones.
3. Guardrails (por ejemplo no tocar `tests/`, aislamiento o límites de permisos)
   y el motor de loop elegido, nombrado explícitamente (`/goal`, `/loop`,
   `ralph-loop`, `claude -p`, routine u otro), idealmente con el comando de
   ejecución para lanzarlo después.

No cuenta en contra que el mensaje diga que no pudo ejecutar scripts, tests o el
validador, ni que cierre con un ofrecimiento o una pregunta, siempre que el
archivo ya esté escrito y nombrado. Tampoco cuenta en contra que el loop no se
haya ejecutado: el usuario pidió expresamente no ejecutarlo.

Falla si: la respuesta se queda en el chat sin escribir ningún archivo; el
archivo se escribió fuera de `.context/loops/` (por ejemplo en `.context/plans/`,
la raíz del proyecto o `/tmp`); no se nombra ninguna condición de parada
verificable; o no se nombra ningún motor de loop.
