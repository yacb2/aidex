# Frontend test shapes (layers 3–5)

The canonical forms for Vitest + Vue Test Utils tests under happy-dom. Layer assignment
is [01-layer-model.md](01-layer-model.md); the `__tests__/` + `__fixtures__/` layout,
its ratchet and the fixture-extraction trigger are
[03-fixtures-convention.md](03-fixtures-convention.md) and are not restated here. One
example per pattern.

## `vitest.config.ts`

```typescript
export default defineConfig({
  plugins: [vue()],
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  test: {
    environment: 'happy-dom',
    globals: true,
    include: ['src/**/__tests__/**/*.test.ts'],  // executable tests only; __fixtures__/ is never collected
    setupFiles: ['./tests/unit/setup.ts'],       // env defaults + the MSW server (below)
  },
  define: {                                      // build-time constants the app reads; tests need a value
    __APP_VERSION__: JSON.stringify('0.0.0-test'),
  },
})
```

`coverage.include` is owed too (`m7`, [03-fixtures-convention.md](03-fixtures-convention.md)).

## Layer 3: composable

```typescript
describe('useCounter', () => {
  it('increments', () => {
    const { count, increment } = useCounter()
    increment()
    expect(count.value).toBe(1)
  })
})
```

## Layer 4: component

**Props and events.** Mount with props, trigger, assert on `emitted()`.

```typescript
it('emits submit on click', async () => {
  const wrapper = mount(ConfirmButton, { props: { label: 'Save' } })
  await wrapper.find('button').trigger('click')
  expect(wrapper.emitted('submit')).toHaveLength(1)
})
```

**Table-driven.** `it.each` when the only thing varying is the input/output pair.

```typescript
it.each([
  ['DRAFT', 'Draft'],
  ['PAID', 'Paid'],
])('renders %s as %s', (status, label) => {
  expect(mount(StatusBadge, { props: { status } }).text()).toContain(label)
})
```

**Pinia.** A fresh store per test, activated before the component mounts.

```typescript
beforeEach(() => setActivePinia(createPinia()))

it('shows the current user', () => {
  useAuthStore().user = { name: 'Test User' }
  expect(mount(UserMenu).text()).toContain('Test User')
})
```

**Router.** Memory history, and `await router.isReady()` before asserting — the initial
navigation is asynchronous.

```typescript
const router = createRouter({
  history: createMemoryHistory(),
  routes: [{ path: '/', name: 'home', component: { template: '<div />' } }],
})

it('renders route-dependent content', async () => {
  const wrapper = mount(Breadcrumb, { global: { plugins: [router] } })
  await router.isReady()
  expect(wrapper.text()).toContain('Home')
})
```

**reka-ui / shadcn-vue primitives.** Local `components/ui/` wrappers mount as-is; a
primitive needing real layout (Dialog, Popover, Combobox) is stubbed — its open/close
interaction is layer 6. Selectors: `data-slot` / `role`, never Tailwind classes
([10-e2e-helper-conventions.md](10-e2e-helper-conventions.md) has the table).

```typescript
mount(InvoiceForm, { global: { stubs: { Dialog: true, DialogContent: true } } })
```

**Async settling.** `flushPromises()` when the work is a resolved promise chain;
`vi.waitFor` when the assertion needs to poll (a debounce, a timer).

```typescript
await flushPromises()
await vi.waitFor(() => expect(wrapper.find('.result').exists()).toBe(true))
```

## `vi.mock` versus MSW

Two different questions, two different tools:

| The test asks | Tool | Layer |
|---|---|---|
| "Given the API client returns X, does this composable compute Y?" — the network is not the subject | `vi.mock('@/lib/api/client')` | 3–4 |
| "Given the server responds with X (including 4xx/5xx), does the UI react correctly?" — the request/response IS the subject | MSW `setupServer` | 5 |

A `vi.mock` of the API client cannot see a wrong URL, method or body: it replaces the
thing that would have noticed, which is exactly what a form-shows-validation-error
test must observe.

**Module mock (layers 3–4):**

```typescript
vi.mock('@/lib/api/client', () => ({ apiClient: { get: vi.fn() } }))
vi.mocked(apiClient.get).mockResolvedValue({ data: { results: [] } })
```

**MSW (layer 5).** One server in `setupFiles`, `onUnhandledRequest: 'error'`
([02-best-practices.md](02-best-practices.md) item 6), handlers overridden per test.

```typescript
// tests/unit/setup.ts
export const server = setupServer()
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }))
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

// in a spec
server.use(
  http.post('*/api/v1/invoices/', () =>
    HttpResponse.json({ number: ['This field is required.'] }, { status: 400 }),
  ),
)
const wrapper = mount(InvoiceForm)
await wrapper.find('form').trigger('submit')
await flushPromises()
expect(wrapper.text()).toContain('This field is required.')
```

Check `package.json` first: a workspace without MSW falls back to `vi.mock` at the cost above.
