# E2E spec shapes (layer 6)

The canonical forms for Playwright specs against the isolated environment
([11-e2e-isolation-infra.md](11-e2e-isolation-infra.md)). Whether a case belongs at
this layer at all is [01-layer-model.md](01-layer-model.md)'s question; the helpers
these shapes call are catalogued in
[10-e2e-helper-conventions.md](10-e2e-helper-conventions.md). One example per pattern.

## Spec skeleton

```typescript
import { test, expect } from '@playwright/test'
import { loginFast, E2E_ADMIN } from '../helpers/auth'
import { navigateToListPage, waitForGrid } from '../helpers/navigation'

test.describe('Invoices', () => {
  test.beforeEach(async ({ page }) => {
    await loginFast(page, E2E_ADMIN)
  })

  test('list page renders the grid', async ({ page }) => {
    await navigateToListPage(page, '/billing/invoices')
    await waitForGrid(page)
    await expect(page.locator('.ag-root')).toBeVisible()
  })
})
```

Helpers, not raw selectors, in the spec body; helper waits (`waitForGrid`,
`waitForResponse`), never `waitForTimeout`.

## Login: API by default, UI once

`loginFast(page, persona)` posts to the DEBUG-gated dev-login endpoint and plants the
JWT cookies — no form, and persona switching is one argument. Every spec uses it
**except the one form-flow spec** (`auth-basic.spec.ts` or equivalent), which keeps the
UI `login()` because that spec IS the login form's coverage. A second spec exercising
the form is duplicate coverage at the slowest layer.

Personas are seed data ([12-e2e-seed-generators.md](12-e2e-seed-generators.md)); their
names live in the project's testing profile (`personas_ref`), never in a spec literal.

## Parametrized CRUD with a run prefix

Config-style entities that share one CRUD flow are one spec driven by a table. Names
carry a `RUN_ID` so a re-run against a preserved database never collides with the
previous run's rows.

```typescript
const RUN_ID = Date.now().toString().slice(-6)
const PREFIX = `E2E_${RUN_ID}_`

const ENTITIES = [
  { name: 'Payment Terms', listPath: '/config/payment-terms', apiPath: 'billing/payment-terms',
    createFields: { Name: `${PREFIX}Net45`, Code: `${PREFIX}N45` } },
]

for (const entity of ENTITIES) {
  test.describe(`CRUD - ${entity.name}`, () => {
    test('create succeeds', async ({ page }) => {
      await navigateToCreatePage(page, `${entity.listPath}/create`)
      for (const [label, value] of Object.entries(entity.createFields)) {
        await fillFieldByLabel(page, label, value)
      }
      const created = page.waitForResponse(r =>
        r.url().includes(`/api/v1/${entity.apiPath}/`) && r.request().method() === 'POST' && r.ok())
      await submitForm(page)
      const { id } = await (await created).json()   // captured for cleanup, not asserted on
      await expectSuccessToast(page)
    })
  })
}
```

## API-response interception

The pattern above is the general one: register `waitForResponse` **before** the action
that triggers the request, match on URL + method + status, then read the body. It is
how a spec learns an id without scraping the DOM, and how a filter change is verified
by the request it sent (`workspace_ids` in the query string) rather than by row
counting.

## Console health

One spec per top-level page: attach the collector before navigation, assert clean
after. A warning is a failure — a console that is allowed to be noisy stops being read.

```typescript
test('no console errors on load', async ({ page }) => {
  const collector = new ConsoleCollector()
  collector.attach(page)
  await navigateToListPage(page, '/billing/invoices')
  const result = collector.assertClean('invoices')
  expect(result.pass, result.message).toBe(true)
})
```

## Email (MailHog)

Clear the mailbox, trigger, wait for the message by recipient + subject, extract.

```typescript
await deleteAllMessages()
await page.goto('/auth/forgot-password')
await page.fill('input[type="email"]', E2E_ADMIN.email)
await page.click('button[type="submit"]')
const email = await waitForEmail(E2E_ADMIN.email, { subject: /reset/i, timeout: 30_000 })
expect(extractPasswordResetLink(email)).toBeTruthy()
```

## Role / permission

Log in as the restricted persona and assert on the **absence** of the affordance. The
403 itself is a layer-2 test; this spec covers only what the browser decides to render.

```typescript
test('viewer has no create button', async ({ page }) => {
  await loginFast(page, E2E_VIEWER)
  await navigateToListPage(page, '/billing/invoices')
  await expect(page.getByRole('link', { name: /new/i })).toHaveCount(0)
})
```

## Data cleanup

The database is recreated from the template at the start of every run, so seed data
needs no cleanup and a spec that only reads needs none either. A spec that **creates**
rows still cleans them in `afterEach` (ids captured by interception, deleted via
`helpers/api.ts`) for one reason: the database is preserved after the run for
debugging, and a later spec in the same run that counts rows must not see them.

Everything a spec creates is `E2E`-prefixed and the cleanup is idempotent (a delete of
an already-deleted id is not a failure).

## Rules for adding a spec

1. **Idempotent.** Runs green twice in a row without `--setup-template` in between.
2. **Stable keys.** Locate seed rows by code / number / email, never by id — ids differ
   between template rebuilds.
3. **Dependency order.** A spec needing seed data that does not exist yet adds the
   generator first ([12-e2e-seed-generators.md](12-e2e-seed-generators.md)), rebuilds
   the template, then writes the spec.
4. **One login per spec file style.** `loginFast` everywhere; UI login only in the form
   spec.
5. **Run it isolated.** `./test-e2e.sh e2e/<name>.spec.ts` — there is no other way to
   run it (`rules/e2e-testing.md`).
