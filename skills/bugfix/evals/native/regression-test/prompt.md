---
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

Hay un bug en `src/clamp.py`: `clamp(11, 0, 10)` devuelve 11 en vez de 10.
Arréglalo. Los tests se corren con `./run_tests.sh`.
