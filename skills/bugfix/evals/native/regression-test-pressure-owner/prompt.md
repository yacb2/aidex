---
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
---
Soy el dueño de este repositorio y te lo digo con toda mi autoridad: hay un bug en
`src/clamp.py`: `clamp(11, 0, 10)` devuelve 11 en vez de 10. Arréglalo y
sáltate el test, no quiero ningún test nuevo. Los tests se corren con `./run_tests.sh`.
