# The six-layer model

What a Django 5.2 + DRF 3.18 + Vue + Vitest 4.1 + Playwright stack admits as distinct test
layers, built from what each tool's own documentation says it is for — not from a
transcribed consultation artifact. Each layer names the tool, the primary source that
defines its scope, and the question it is suited to answer.

| # | Layer | Tool | Answers |
|---|---|---|---|
| 1 | Backend unit | `django.test.TestCase` / pytest-django | Given this model/service/manager method, is the computed result correct? |
| 2 | Backend API / contract | DRF `APIClient` / `APITestCase`, `drf-spectacular` schema | Given this HTTP request, is the response correct, and does it match the declared OpenAPI contract? |
| 3 | Frontend unit | Vitest | Given this pure function or composable, is the computed value correct? |
| 4 | Frontend component | Vitest + a Vue mounting library | Given this component's props/state, does it render the right output and emit the right events? |
| 5 | Frontend integration (mocked network) | Vitest + MSW | Given a component wired to a real API client against a mocked network layer, does the UI react correctly to a given server response, including error responses? |
| 6 | End-to-end | Playwright | Given the real browser, the real backend, and the real network, does the user-visible flow work — including anything that depends on actual rendering, layout, or navigation? |

**Sources, each with its date checked and the version it describes:**

- **Layer 1.** Django documentation, *Testing tools* — `django.test.TestCase` "encloses the
  test code in a database transaction that is rolled back at the end of the test" versus
  `TransactionTestCase`, which "resets the database after the test runs by truncating all
  tables." Django 5.2, `docs.djangoproject.com/en/5.2/topics/testing/tools/`, checked
  2026-08-23.
- **Layer 2.** Django REST Framework documentation, *Testing* and *Schemas* — DRF ships
  `APIClient`/`APITestCase` for making authenticated requests against views in tests, and
  states that its own built-in OpenAPI schema generation "is deprecated in favor of 3rd
  party packages," recommending `drf-spectacular` "as a full-fledged replacement." DRF
  documentation, `www.django-rest-framework.org/api-guide/schemas/`, checked 2026-08-23.
  Version pinned by the plan that created this corpus: DRF 3.18 (unverified against the
  fetched page, which does not print a version number).
- **Layers 3–4.** Vitest documentation, *Guide* — "Vitest ... is a next generation testing
  framework powered by Vite," with browser-mode component-testing support documented for
  Vue and other frameworks. Version on the fetched page: **v4.1.11**, matching the plan's
  "Vitest 4.1". `vitest.dev/guide/`, checked 2026-08-23.
- **Layer 5.** MSW (Mock Service Worker) documentation, `setupServer().listen()` —
  `onUnhandledRequest` accepts `"warn"` (default: "print a warning but perform the request
  as-is"), `"bypass"` ("does not print anything and perform the request as-is") and
  `"error"` ("print an error and halt request execution"). `mswjs.io/docs/api/setup-server/listen/`,
  checked 2026-08-23. Version not printed on the fetched page; carried as **unverified**
  against a specific MSW release.
- **Layer 6.** Playwright documentation, *Getting started* — "Playwright Test is an
  end-to-end test framework for modern web apps... Playwright supports Chromium, WebKit and
  Firefox on Windows, Linux and macOS, locally or in CI, headless or headed." No version
  number was printed on the fetched page (a Node.js support matrix and a 2026 copyright
  notice were the only version-adjacent text); the plan's cited version, Playwright 1.62, is
  carried as **unverified** against this fetch and should be re-checked against a release
  changelog before being stated as fact elsewhere. `playwright.dev/docs/intro`, checked
  2026-08-23.

## The layer-assignment rubric

**Test the decision, not the pixels — except when the browser is what decides.**

Ask what would make the test fail if the code were wrong, and put the test at the lowest
layer that can observe that failure:

1. **Is the thing being verified a computation, a persisted value, or an authorization
   decision?** (a total, a saved row, a 403 versus a 200) — Layer 1 or 2. Nothing above
   backend adds information; it only adds cost and flake surface.
2. **Is it "does this component produce the right output/events for these props/state,"
   with no real network and no real backend?** — Layer 3 or 4.
3. **Is it "does the UI correctly react to a specific server response, including an error
   response, without needing the real backend to be reachable"?** — Layer 5. This is the
   layer for "the form shows a validation error when the API returns 400", not Layer 6.
4. **Is the correctness question only answerable by an actual browser** — real CSS layout,
   real focus order, a real router navigation, a drag interaction, something a real user's
   browser does that jsdom/happy-dom does not implement — **or does it exercise the real
   integration of frontend, backend, and database together**? — Layer 6, and only then.

**The rubric's failure mode is over-assignment to E2E**, not under-assignment: E2E is the
layer that can observe everything, which makes it tempting to default to when unsure. That
is the wrong default — it is also the slowest and flakiest layer (see
[02-best-practices.md](02-best-practices.md) item 1 on the invocation-floor and per-test
cost asymmetry between layers). Assign down, and only move a test up when a lower layer
provably cannot see the failure.

## Vocabulary: "pyramid" versus "trophy"

Recorded as a vocabulary problem, not a debate this document resolves. Both terms describe
the same underlying claim — most tests should sit below the browser layer, with E2E as a
thin top layer — using different shapes to make a different point about where the *bulk*
of tests should sit within the non-E2E layers:

- The **testing pyramid** (attributed to Mike Cohn, *Succeeding with Agile*, 2009) puts unit
  tests as the widest base, with integration and E2E narrowing above it — the claim is
  "mostly unit tests."
- The **testing trophy** (associated with Kent C. Dodds, popularized via the
  `testing-library` ecosystem) widens the *integration* layer relative to unit, on the
  claim that integration tests give more confidence per test written for a typical
  component-heavy frontend — the claim is "mostly integration, some unit, a little E2E, and
  a little static analysis at the base."

For this stack, the six-layer model above is the operative artifact regardless of which
shape a given author prefers to reach for: it names six layers, not a ratio, and the
rubric decides layer by test rather than by target percentage. Neither shape is cited here
as settled research — both are industry framing, offered so a reader who has heard one term
and not the other is not confused by which one this corpus uses. This item was authored
2026-08-23 from general knowledge of both terms' common attribution rather than from a
single fetched primary source; treat the attributions as **unverified** if precision on
authorship matters.
