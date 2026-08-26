# E2E helper conventions

Helpers are **standalone async functions**, not Page Objects. A Page Object binds a
selector set to a class instance and pulls the spec toward the class's vocabulary; a
function taking `page` composes with any other function and keeps the spec readable as
a list of user actions. Specs call helpers; helpers own selectors.

## Taxonomy

One file per concern under the project's `helpers_dir` (a fact in the testing profile,
[14-testing-profile.md](14-testing-profile.md)). A helper that fits none of these gets
a new file named for its concern (`pdf.ts`), never a `misc.ts`.

| File | Owns | Needs a browser |
|---|---|---|
| `auth.ts` | `loginFast` (API), `login` (UI form), logout, persona constants | yes |
| `navigation.ts` | go to list/create page, `waitForGrid`, `fillFieldByLabel`, `submitForm`, toast and dialog assertions, row action menu | yes |
| `ag-grid.ts` | sort, filter, pagination, column manager, grid `localStorage` state | yes |
| `workspace.ts` | workspace switcher, multi-select, change-and-wait-for-refresh | yes |
| `api.ts` | DELETE for cleanup, using the browser's cookies | yes |
| `api-factory.ts` | GET/POST for data setup, standalone token | no |
| `console.ts` | `ConsoleCollector`: attach, `assertClean` | yes |
| `mailhog.ts` | `deleteAllMessages`, `waitForEmail`, link extraction over the MailHog HTTP API | no |

## Rules

1. **`page` is the first argument** of every browser helper; the rest are plain values.
   ```typescript
   export async function clickActionMenuItem(page: Page, text: string): Promise<void>
   ```
2. **Base URL comes from `test-config.ts`**, never a literal. `TEST_CONFIG.FRONTEND_URL`
   and `TEST_CONFIG.API_BASE` are env-driven ([11-e2e-isolation-infra.md](11-e2e-isolation-infra.md));
   a hardcoded port is the bug that makes a spec pass on the author's machine and drive
   the wrong stack in a worktree.
3. **Fix a selector in the helper, not in the specs.** A UI-library upgrade that changes
   a `data-slot` is one edit in `navigation.ts`, not one per spec. If a selector had to
   be written inline in a spec, that is the signal a helper is missing.
4. **A helper is extracted at the third use** — the same rule-of-three as everywhere
   else ([03-fixtures-convention.md](03-fixtures-convention.md)) — or immediately when
   the interaction is multi-step (open menu, wait for it, click item, wait for URL).
5. **Waits are inside helpers.** `waitForGrid` waits for `.ag-root` visible AND the
   loading overlay hidden; a spec never writes that pair itself, and never
   `waitForTimeout`.

## Stack-default selectors

Defaults for the family's UI stack. Projects declare theirs in the profile's `ui_stack`;
a project on a different library keeps this table's *shape* and swaps the values, in
the helpers only.

| Element | Library | Selector |
|---|---|---|
| Dialog / Sheet | shadcn-vue | `[role="dialog"]` |
| Alert dialog (delete confirm) | shadcn-vue | `[role="alertdialog"]` |
| Context menu | shadcn-vue | `[data-slot="context-menu-content"]` |
| Context menu item | shadcn-vue | `[data-slot="context-menu-item"]` |
| Combobox trigger | reka-ui | `button[role="combobox"]` |
| Option | reka-ui | `[role="option"]` |
| Popover content | reka-ui | `[data-radix-popper-content-wrapper]` |
| Toast (success) | vue-sonner | `[data-sonner-toast][data-type="success"]` |
| Toast (error) | vue-sonner | `[data-sonner-toast][data-type="error"]` |
| Grid root | AG-Grid | `.ag-root` |
| Grid rows | AG-Grid | `.ag-center-cols-container .ag-row` |
| Grid loading overlay | AG-Grid | `.ag-overlay-loading-center` |

Prefer `role` and `data-slot` over class names: the classes are Tailwind output and
change with any restyle. Button text in a locale-specific UI comes from the profile's
`ui_locale`, not from a hardcoded string in the helper.

## `api-factory.ts` contract

The standalone layer for data setup: no browser, one cached token, plain `fetch`
against `TEST_CONFIG.API_BASE`. Three functions are the contract; entity-specific
creators (`createTestSupplier`) are thin wrappers over `apiCreate`.

```typescript
let cachedToken: string | null = null

export async function ensureApiToken(persona = E2E_ADMIN): Promise<string> {
  if (cachedToken) return cachedToken
  const res = await fetch(`${TEST_CONFIG.API_BASE}/auth/login/`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(persona),
  })
  if (!res.ok) throw new Error(`Login failed: ${res.status}`)
  cachedToken = (await res.json()).access
  return cachedToken!
}

export async function apiGet<T = unknown>(path: string): Promise<T> {
  const res = await fetch(`${TEST_CONFIG.API_BASE}/${path.replace(/^\//, '')}`,
    { headers: { Authorization: `Bearer ${await ensureApiToken()}` } })
  if (!res.ok) throw new Error(`GET ${path} failed: ${res.status}`)
  return res.json()
}

export async function apiCreate<T = unknown>(path: string, data: object): Promise<T> {
  const res = await fetch(`${TEST_CONFIG.API_BASE}/${path.replace(/^\//, '')}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await ensureApiToken()}` },
    body: JSON.stringify(data),
  })
  if (!res.ok) throw new Error(`POST ${path} failed: ${res.status} - ${await res.text()}`)
  return res.json()
}
```

`api.ts` is the other half — cleanup through the **browser's** session, because delete
endpoints in this family are cookie-authenticated and the standalone token cannot
reach them. Keep the two files separate; merging them hides which one a helper needs.

## Adapting to a project

| What changes | Where |
|---|---|
| Persona credentials | `auth.ts` constants, sourced from `personas_ref` |
| Login form fields | `auth.ts` `login()` only |
| Toast / dialog / menu selectors | `navigation.ts` only |
| Login endpoint and token field | `api-factory.ts` `ensureApiToken` only |
