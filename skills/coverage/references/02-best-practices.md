# Best-practice corpus

**Authoring constraint.** Each item below is written from its own primary source, with
that source's date and the tool version it describes. Nothing here is transcribed from a
consultation artifact or a session transcript — those are not verifiable sources. Where a
fetch could not confirm a specific claim (most often a version number), the item says so
explicitly with **unverified** rather than stating it as settled.

Item numbering is stable and is referenced from `SKILL.md` and `06-judgment-pass.md`;
an item whose content moved to a stack pack keeps its number as a pointer.

---

## 1. The 2026-08-21 primary-source sweep, re-run against current versions

This file **is** that re-run, dated 2026-08-23. Fetched and quoted directly, rather than
assumed from training knowledge: Django's *Testing tools* and *Testing overview* pages
(5.2, `docs.djangoproject.com/en/5.2/...`), the `post_migrate` signal reference page,
pytest-django's `helpers.html` and `database.html` (version not printed on the fetched
pages), pytest-xdist's `distribution.html`, DRF's `schemas.html`, MSW's
`setup-server/listen/`, Vitest's `guide/` (confirmed v4.1.11), and Playwright's `intro`
page (version not printed). Every claim below that carries a source line was checked
against one of these fetches on 2026-08-23, not reconstructed from memory.

## 2. The `transaction=True` finding

Moved to the `testing-django` stack pack (`references/02-pytest-django-traps.md`) on
2026-08-27: it is a pytest-django trap, not doctrine.

## 3. The `-n`-with-`--reuse-db` orphaned-database trap

Moved to the `testing-django` stack pack (`references/02-pytest-django-traps.md`) on
2026-08-27, with item 2.

## 4. The multi-tenant isolation rule

**Status: a general access-control testing principle, not a stack-specific finding —
authored here without a project-specific tenancy library in scope**, because no ledger
entry or research document in this chain names one (checked: no occurrence of "tenant" in
`.context/research/2026-08-22-suite-speed-and-coverage-findings/` outside the single
mention in `05-open.md`'s undischarged-corpus list). The rule stated is the general OWASP
principle applied to Django/DRF: **a queryset-level authorization test must assert that
cross-tenant (or cross-owner) data is *absent* from the response, not only that same-tenant
data is present.** The OWASP Testing Guide's authorization-testing category (Broken Object
Level Authorization / IDOR-class checks) states the general form of this requirement —
verifying that an authenticated actor cannot retrieve or act on another actor's resource by
varying an identifier — as a standard web-application test class, independent of any
specific ORM or framework. This item is marked **unverified against a fetched OWASP page**
(no fetch was made for it in this pass); it is stated as a well-established security-testing
category rather than sourced to a specific quoted line, and should be re-sourced with a
direct fetch before being treated as a quoted primary-source claim on the level of items
1–3 and 6.

**Concrete form for this stack:** a DRF `APITestCase` (Layer 2) that creates two tenants (or
two owning users), authenticates as one, and asserts the other tenant's rows are excluded
from a list/detail response and that a direct-by-id request for the other tenant's object
returns 403/404 rather than 200. This belongs at Layer 2 under the rubric in
[01-layer-model.md](01-layer-model.md): it is an authorization decision, not a rendering
question.

## 5. The OpenAPI contract layer

**Confirmed, from DRF's own documentation:** "REST framework's built-in support for
generating OpenAPI schemas is deprecated in favor of 3rd party packages" and will be "moved
into a separate package and then subsequently retired over the next releases." DRF
recommends `drf-spectacular` "as a full-fledged replacement," describing it as having
"extensive support for generating OpenAPI 3 schemas from REST framework APIs, with both
automatic and customizable options available." DRF docs,
`www.django-rest-framework.org/api-guide/schemas/`, checked 2026-08-23.

**Why this is a named gap for this stack, per the programme's own state-of-the-world
finding:** the 2026-08-21 static census recorded "two layers absent entirely: OpenAPI
contract diffing and mutation testing" (`.context/decisions/2026-08-22-suite-speed-and-coverage-programme.md`,
*State before any change*). This item gives that gap a concrete remedy — `drf-spectacular`
schema generation plus a contract-diff check in CI or pre-commit against the last-committed
schema snapshot — without claiming the remedy has been applied anywhere in this fleet.
Closing the gap is explicitly out of scope for this plan phase; `q4` (automatic control) is
answered elsewhere in the ADR as "fast local pre-commit only, linters, never the suite," so
a contract-diff check that runs the app is not automatically compatible with that
constraint and would need its own scoping decision before adoption, not an assumption of
one here.

## 6. MSW's `onUnhandledRequest: 'error'`

Moved to the `testing-vue` stack pack (`references/02-msw-traps.md`) on 2026-08-27: it
is an MSW trap, not doctrine.

## 7. The pyramid-versus-trophy resolution

See [01-layer-model.md](01-layer-model.md), "Vocabulary: 'pyramid' versus 'trophy'" — a
vocabulary problem, not a debate this corpus takes a side on. Recorded here as the sourcing
rule requires (it belongs to this sweep, per the plan's Task 3.1), with the same
**unverified-attribution** caveat stated there: the Cohn/pyramid and Dodds/trophy
attributions are common industry knowledge, not independently re-confirmed against a
fetched primary source in this pass.

## 8. The six-layer model and its layer-assignment rubric

See [01-layer-model.md](01-layer-model.md) in full — six layers, each tied to the tool
documentation that defines its scope, plus the rubric ("test the decision, not the pixels
— except when the browser is what decides"). Recorded here as the index entry the sourcing
rule requires; not duplicated in this file.
