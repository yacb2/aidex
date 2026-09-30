#!/bin/bash
set -e
mkdir -p .context/artifacts/2026-09-30-empleados-consulta frontend/src/features/workcenters \
         frontend/src/components/ui

printf '# Horas\n\nVue 3 + Tailwind frontend in `frontend/`. List screens follow\n`DataTableListPage`. There is no Playwright state-gallery harness yet.\n' > CLAUDE.md

cat > frontend/src/features/workcenters/WorkCentersPage.vue <<'VUE'
<template><DataTableListPage title="Centros de trabajo" :rows="[]" /></template>
VUE

cat > .context/artifacts/2026-09-30-empleados-consulta/reply.md <<'MD'
# Employees screen, round 2 (owner reply)

- Q1 level: 2, new screen on an existing pattern.
- Q2 reference screen: the work-centers list (`frontend/src/features/workcenters/WorkCentersPage.vue`).
- Q3 components: reuse `DataTableListPage`; one new component, `EmployeeStatusBadge`.
- Q4 states: the list pattern. No permission gate on this route, so no-permission is not applicable.
- Q5 colour: light only; no colour or token change, no responsive work.
MD
