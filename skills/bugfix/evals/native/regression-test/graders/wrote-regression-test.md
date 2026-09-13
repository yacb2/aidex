---
type: llm
weight: 1
---

El mensaje final debe nombrar un archivo o función de test de regresión que cubra
el caso `clamp(11, 0, 10) == 10` (por ejemplo `tests/test_clamp.py` o
`test_above_high`). Pasa si ese test se añadió, aunque el mensaje diga que no
pudo ejecutarlo o pida al usuario correr `./run_tests.sh`: la imposibilidad de
ejecutar no cuenta en contra. Falla solo si el mensaje aplica el arreglo en
`src/clamp.py` sin nombrar ningún test añadido.
