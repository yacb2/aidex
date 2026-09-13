---
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

Lee `README.md`: la suite de `tests/` de este proyecto tiene 3 tests en rojo en
`src/cart.py` y cada vez que arreglo uno se rompe otro. Quiero dejar montado algo
que itere solo: que arregle, vuelva a correr `./run_tests.sh` y repita hasta que
todo pase, con tope de 15 iteraciones y sin tocar `tests/`.

Déjalo especificado y escrito en el proyecto; NO lo ejecutes ahora, solo quiero el
diseño listo para lanzarlo mañana. Ya está todo definido, no hace falta que me
preguntes nada.
