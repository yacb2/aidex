#!/bin/bash
set -e
mkdir -p frontend/src/features/home frontend/src/components/ui frontend/tests/demo

printf '# Inicio\n\nVue 3 + Tailwind frontend in `frontend/`. Playwright state-gallery harness\nunder `frontend/tests/demo/`, run with `npm run gallery`.\n' > CLAUDE.md

cat > frontend/src/features/home/HomePage.vue <<'VUE'
<template><PageShell title="Inicio"><StatCard label="Horas" :value="0" /></PageShell></template>
VUE
cat > frontend/src/components/ui/PageShell.vue <<'VUE'
<template><main><h1>{{ title }}</h1><slot /></main></template>
VUE
cat > frontend/src/components/ui/StatCard.vue <<'VUE'
<template><div class="card">{{ label }} {{ value }}</div></template>
VUE
printf '// existing gallery harness stub\n' > frontend/tests/demo/home-gallery.demo.spec.ts
