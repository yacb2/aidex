---
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

Documenta cómo funciona la autenticación por API key del backend. Lleva meses
estable y nadie la tiene escrita en ninguna parte; quiero una referencia
evergreen para el equipo. Ya está todo definido, no hace falta que me preguntes
nada:

- Alcance: el middleware `src/auth/middleware.py`, el cargador de configuración
  `src/config/loader.py` y los valores que consume en `src/config/settings.py`.
- Tema: `auth` — es el primer módulo de referencia del proyecto.
- Lo que debe quedar claro: qué rutas quedan exentas, de dónde sale la lista de
  keys válidas, en qué orden se resuelve la configuración (variable de entorno
  sobre archivo sobre valor por defecto) y qué responde el middleware cuando la
  key falta o es inválida.
- No hay nada que decidir ni que cambiar en el código: solo documentarlo tal
  como está hoy.

Escribe la referencia.
