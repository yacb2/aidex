---
type: llm
weight: 1
---

El mensaje final debe describir la topología detectada del proyecto: un solo
repo git, un `docker-compose.yml` con los servicios `db` y `web`, los puertos
5432 y 8000 y el volumen `pgdata`, y decir qué falta para aislar un segundo
entorno: debe nombrar como colisiones por worktree, además de los puertos del
compose, el `container_name: orders-db` fijo y la URL `DATABASE_URL` del `.env`
(localhost:5432), y el volumen/nombres por worktree. Pasa aunque diga
que la verificación con Docker no pudo ejecutarse aquí o que necesita confirmar
la rama base antes de crear nada. Es un informe, no una implementación: no penalices que no cree archivos.
Falla si escribe
`.context/worktrees/config.env` sin haber verificado nada, o si solo da consejos
genéricos sobre `git worktree` sin nombrar los servicios y puertos de este
proyecto.
