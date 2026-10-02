#!/bin/bash
set -e
mkdir -p .context/artifacts/2026-10-02-usuarios-consulta frontend/src/features/users \
         frontend/src/features/access frontend/src/components/ui

printf '# Acceso\n\nVue 3 + Tailwind frontend in `frontend/`. List screens follow\n`DataTableListPage`. There is no Playwright state-gallery harness yet.\n' > CLAUDE.md

cat > frontend/src/features/users/UsersPage.vue <<'VUE'
<template>
  <DataTableListPage title="Usuarios" :rows="[]">
    <template #actions><button @click="showInvite = true">Añadir usuario</button></template>
  </DataTableListPage>
  <InviteUserDialog v-if="showInvite" />
</template>
VUE

cat > frontend/src/features/users/InviteUserDialog.vue <<'VUE'
<template><dialog open><form><input name="email" /><button>Invitar</button></form></dialog></template>
VUE

cat > frontend/src/features/access/ProjectAccessView.vue <<'VUE'
<template><section>Accesos por proyecto de una persona</section></template>
VUE

cat > .context/artifacts/2026-10-02-usuarios-consulta/reply.md <<'MD'
# Users screen, round 1 (owner reply)

- Level: 2, existing list pattern.
- Reference screen: `frontend/src/features/users/UsersPage.vue`.
- Components: reuse `DataTableListPage`; add a filter bar.
- The change redesigns the users list and the per-project access view of a person
  (`frontend/src/features/access/ProjectAccessView.vue`) that the list links to.
- Light only; no colour or token change.
MD
