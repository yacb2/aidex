---
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

Quiero que diseñes, sin ejecutarla, una orquestación de varios agentes en paralelo
que revise `src/auth.py`, `src/payments.py`, `src/notifications.py` y
`src/reports.py` en dos dimensiones: corrección y seguridad. Necesito el modelo y el
esfuerzo asignados a cada agente, y la regla que dice qué tiene que cumplir la salida
de cada uno para darse por buena. Es una sola pasada, no algo que se repita.

Déjalo todo escrito, no lo lances todavía. Ya está todo definido, no hace falta que
me preguntes nada. Al final dime dónde quedó.

Escribe el workflow-spec exactamente en
`.context/workflows/2026-09-16-revision-modulos.md`; no cambies ese nombre de archivo.
