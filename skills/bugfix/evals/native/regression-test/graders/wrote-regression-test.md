---
type: llm
weight: 1
---

Lo único que se juzga aquí es la SUSTANCIA: que el mensaje final reporte haber
añadido un test de regresión para el caso `clamp(11, 0, 10) == 10` ANTES de
tocar `src/clamp.py`, y que el arreglo aplicado sea el mínimo (devolver `high`
cuando el valor supera el techo).

NO cuenta en contra que diga que no pudo ejecutar `./run_tests.sh` o que pida al
usuario correrlo: la imposibilidad de ejecutar no cuenta en contra.

Falla si el mensaje reporta haber arreglado `src/clamp.py` sin ningún test de
regresión, o si cambió el test existente en vez de añadir uno.

El contenido del archivo de test NO se juzga aquí — lo asserta
`regression-test-structure` sobre `tests/test_clamp.py`.
