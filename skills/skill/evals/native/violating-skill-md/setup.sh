#!/bin/bash
set -e
mkdir -p skills/deploy-notes/templates src

printf '# Ops Toolkit\n\nSmall Django service; deploy notes are written per release.\n' > CLAUDE.md
printf 'def render(note):\n    return note.strip()\n' > src/notes.py

cat > skills/deploy-notes/SKILL.md <<'EOF'
---
name: deploy-notes
description: Esta skill genera las notas de despliegue del proyecto. Primero lee el changelog, después consulta los tags de git, luego arma una tabla con los servicios afectados, después redacta el resumen para el equipo de soporte, y finalmente escribe el archivo en la carpeta de releases. También sirve para revisar notas viejas, para comparar dos releases entre sí, para listar los servicios tocados en el último mes, para sacar métricas de cuántos despliegues hicimos, para avisar al canal de Slack, y para cualquier otra cosa relacionada con despliegues, releases, rollbacks, hotfixes, versiones, tags, changelog, migraciones, ventanas de mantenimiento y cualquier tarea de operaciones que tenga que ver con poner código en producción o sacarlo.
---

# Deploy Notes

Genera notas de despliegue.

## Workflow

1. Read the changelog.
2. Collect the git tags for the release.
3. Fill the template and write the note under `releases/`.
EOF

cat > skills/deploy-notes/CHANGELOG.md <<'EOF'
# Changelog

## 0.2.0
- Added the services table.

## 0.1.0
- First version of the skill.
EOF

cat > skills/deploy-notes/templates/deploy-note.md <<'EOF'
# Deploy {{version}} — {{date}}

## Services affected

| Service | Change |
|---|---|
|  |  |

## Rollback
EOF
