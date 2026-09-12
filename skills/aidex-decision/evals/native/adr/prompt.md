---
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

Decidimos migrar la cola de tareas de Celery a Dramatiq: menos infraestructura
(sin broker Redis dedicado), mejor ergonomía de reintentos y una base de código
más pequeña. Evaluamos también quedarnos en Celery y usar RQ. Documenta la
decisión.
