#!/bin/bash
set -e
mkdir -p .context/plans frontend/src/features/employees frontend/src/features/workcenters \
         frontend/src/components/ui frontend/tests/demo

printf '# Horas\n\nVue 3 + Tailwind frontend in `frontend/`. List screens follow\n`DataTableListPage`; forms follow `FormLayout`. Playwright specs live in\n`frontend/tests/`.\n' > CLAUDE.md

cat > frontend/src/features/workcenters/WorkCentersPage.vue <<'VUE'
<script setup lang="ts">
import { ref, onMounted } from 'vue'
import DataTableListPage from '@/components/ui/DataTableListPage.vue'
import { listWorkCenters } from './api'

const rows = ref([])
const loading = ref(true)
const error = ref<string | null>(null)

onMounted(async () => {
  try {
    rows.value = await listWorkCenters()
  } catch (e) {
    error.value = String(e)
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <DataTableListPage
    title="Centros de trabajo"
    :rows="rows"
    :loading="loading"
    :error="error"
  />
</template>
VUE

cat > frontend/src/components/ui/DataTableListPage.vue <<'VUE'
<script setup lang="ts">
defineProps<{
  title: string
  rows: unknown[]
  loading?: boolean
  error?: string | null
}>()
</script>

<template>
  <section>
    <h1>{{ title }}</h1>
    <p v-if="loading">Cargando…</p>
    <p v-else-if="error">{{ error }}</p>
    <slot v-else name="table" :rows="rows" />
  </section>
</template>
VUE

cat > frontend/src/features/employees/api.ts <<'TS'
export interface Employee {
  id: number
  name: string
  workCenterId: number
  active: boolean
}

export async function listEmployees(params: { q?: string } = {}): Promise<Employee[]> {
  const query = params.q === undefined ? '' : `?q=${encodeURIComponent(params.q)}`
  const response = await fetch(`/api/employees/${query}`)
  if (!response.ok) throw new Error(`HTTP ${response.status}`)
  return response.json()
}
TS

cat > frontend/tests/demo/state-gallery.ts <<'TS'
/**
 * State-gallery harness. One Playwright test per state-matrix cell.
 *
 * `runListGallery(gallery)` takes { name, slug, path, cells }, where `cells` is an
 * exhaustive record over the list states. `validateMatrix` refuses, at run time, a
 * missing cell and a not-applicable cell whose `reason` is blank.
 *
 * Runs through `playwright.demo.config.ts` only, always with a spec path.
 */
export const LIST_STATES = [
  'with-data',
  'empty',
  'filtered-empty',
  'loading',
  'error',
  'no-permission',
] as const
TS

cat > .context/plans/2026-09-21-pantalla-de-empleados.md <<'MD'
---
title: "Employees list screen"
status: open
mode: scoped
created: 2026-09-21
updated: 2026-09-21
---

# Employees list screen

**Goal:** add a list screen for employees, modelled on the existing work-centers list.

**Non-goals:** no new API endpoint (`listEmployees()` already exists); no edit form.

---

# Phase 1: the employees list screen  (tier: standard, phase-type: afk-impl, tests: component)

**Files:**
- Create: `frontend/src/features/employees/EmployeesPage.vue`
- Modify: `frontend/src/router/index.ts`

**Out of scope:** the employee detail form.

**Acceptance:**
1. `/employees` renders the employees returned by `listEmployees()`.
2. The search box filters server-side.

## Phase 1 Checkpoint

- [ ] Task 1.1: the page
- [ ] Task 1.2: the route

## Execution log
MD
