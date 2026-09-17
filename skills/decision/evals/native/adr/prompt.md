---
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

Decidimos migrar la cola de tareas de Celery a Dramatiq: menos infraestructura
(sin broker Redis dedicado), mejor ergonomía de reintentos y una base de código
más pequeña. Evaluamos también quedarnos en Celery y usar RQ. Documenta la
decisión.

Guárdalo exactamente en `.context/decisions/2026-09-16-migrar-cola-a-dramatiq.md`;
no cambies ese nombre de archivo.
