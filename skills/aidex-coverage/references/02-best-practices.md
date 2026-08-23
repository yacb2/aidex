# Best-practice corpus

**Authoring constraint, non-negotiable (carried forward from the plan that created this
file).** Each item below is written from its own primary source, with that source's date
and the tool version it describes. Nothing here is transcribed from the 2026-08-21/22
consultation artifact or from session transcripts — those are not verifiable sources, and
copying them into this corpus would reproduce the exact failure this topic exists to
correct. Where a fetch could not confirm a specific claim (most often a version number),
the item says so explicitly with **unverified** rather than stating it as settled.

Stack versions this sweep targeted, per the plan: Django 5.2, pytest-django 4.14, DRF 3.18,
Vitest 4.1, Playwright 1.62. Not every one of those version numbers could be independently
confirmed against a fetched page in this pass — each item states what was and was not
confirmed.

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

**Status: candidate with its mechanism stated, not a recommended lever.** `m1` — measure a
lever before the playbook recommends it — forbids promoting this to a lever list entry
without a measurement, and none was taken here: the corpus reports it as being of the same
order as the levers this campaign's round two did measure, on a per-model count of NS
(`ns_Z1_model_count`: 95 models) that nobody timed. Presenting it as equivalent to the
measured hasher/xdist/`debug_toolbar` figures would be exactly the false-confidence failure
`m1` exists to prevent.

**The mechanism, confirmed against Django 5.2 primary sources:**

- `TransactionTestCase` "resets the database after the test runs by truncating all tables,"
  where `TestCase` instead "encloses the test code in a database transaction that is rolled
  back at the end of the test." Django docs, *Testing tools*,
  `docs.djangoproject.com/en/5.2/topics/testing/tools/`, checked 2026-08-23.
- The `post_migrate` signal is "sent at the end of the migrate (even if no migrations are
  run) and flush commands." Django docs, *Signals reference*,
  `docs.djangoproject.com/en/5.2/ref/signals/#post-migrate`, checked 2026-08-23.
- Django's *Testing overview* page confirms the two are connected for `TransactionTestCase`:
  it documents `serialized_rollback=True` as a flag that "disables the post_migrate signal
  when flushing the test database" specifically to prevent serialized fixture data from
  being reloaded twice — which is only a meaningful flag to expose if `post_migrate` fires
  on the ordinary (non-serialized-rollback) path. Docs also state that turning
  `serialized_rollback` on "will slow down that test suite by approximately 3x," which is
  a *different*, already-quantified cost on the same signal, not the cost this item is
  about. Django docs, *Testing overview*,
  `docs.djangoproject.com/en/5.2/topics/testing/overview/`, checked 2026-08-23.
- `django.contrib.contenttypes` and `django.contrib.auth` connect their own
  `post_migrate` handlers (`create_contenttypes`, `create_permissions`) to recreate a
  project's `ContentType` and `Permission` rows after every flush — this is documented
  behaviour of those two contrib apps' `AppConfig.ready()` wiring, not something this sweep
  independently fetched a quote for; treat the specific handler names as **unverified**
  against a fetched page, though the general mechanism (contenttypes/permissions
  regenerate after a flush) is confirmed by the `post_migrate`-on-`flush` fact above plus
  the `serialized_rollback` interaction.

**Why it matters at scale, unmeasured:** every `TransactionTestCase` (and anything that
truncates rather than rolls back — `pytest.mark.django_db(transaction=True)` in
pytest-django terms) pays a `post_migrate` flush on top of the truncation itself, on a
per-model-count basis. Round two's `ns_Z1_model_count` put NS at 95 models, i.e. roughly 95
content types plus ~380 permissions recreated per truncating test — a cost nobody has
timed, hence "candidate," not "lever."

**The alternative, confirmed:** `TestCase.captureOnCommitCallbacks(using=DEFAULT_DB_ALIAS,
execute=False)` — "returns a context manager that captures `transaction.on_commit()`
callbacks for the given database connection" — lets a test assert on or execute
on-commit callbacks *without* switching to `TransactionTestCase`/`transaction=True`. Django
docs, *Testing tools*, checked 2026-08-23. pytest-django exposes the equivalent as the
`django_capture_on_commit_callbacks` fixture, and its own docs explicitly warn: "avoid this
fixture in tests using `transaction=True`; you are not likely to get useful results" —
i.e. the fixture is specifically the non-truncating alternative, and combining it with the
expensive mode is self-defeating. pytest-django docs, `helpers.html`, checked 2026-08-23
(pytest-django version not printed on the fetched page; plan's stated version 4.14 is
**unverified** against this fetch).

## 3. The `-n`-with-`--reuse-db` orphaned-database trap

**The trap, confirmed:** pytest-django's `--reuse-db` "will create the test database in the
same way as `manage.py test` usually does. However, after the test run, the test database
will not be removed" — by design, so a subsequent run "will instantly be reused." Under
pytest-xdist, each worker gets its own suffixed database via the
`django_db_modify_db_settings_parallel_suffix` fixture, which "will add a suffix to the
database name when the tests are run via pytest-xdist." Combine the two and an interrupted
`-n`-parallel run leaves one persistent, suffixed database per worker that was never
cleaned up — the trap is real by construction, not by observation. pytest-django docs,
`database.html`, checked 2026-08-23.

**The `loadfile`-over-`loadscope` rationale is struck from this item and must not be
authored as a preference.** Round two measured the two at n=8, interleaved:
`loadfile` 267.5 s against `loadscope` 272.0 s — **1.7% apart, inside the noise**.
`05-open.md` §B recorded a preference for `loadfile` that was a rationale, not a result, and
`ns_backoffice_ws` keeps `loadscope` for the unrelated reason that it is already what is in
use there. Source: `research/2026-08-22-suite-speed-and-coverage-findings/10-round2-results.md`,
"`loadfile` vs `loadscope`: a tie, and the preference was never a measurement." Author the
trap; author the tie; author neither preference.

**What pytest-xdist's own docs say about the two modes, confirmed:** `--dist loadscope`
groups "by module for test functions and by class for test methods... useful if you have
expensive module-level or class-level fixtures," and guarantees "all tests in a group run
in the same process." `--dist loadfile` groups "by their containing file," also guaranteeing
same-worker execution per group. pytest-xdist docs, `distribution.html`, checked 2026-08-23;
the fetched page states no preference between the two, consistent with round two's tie.

**Census note, from round two, not re-measured here:** a read-only census before and after
every xdist row in the round-two campaign found 18 databases before and 18 after — nothing
leaked in that run. That is an observation about one campaign, not a guarantee: the run did
not include the specific hazard case (an interrupted `-n` + `--reuse-db` run), so the trap
above stands on the documented mechanism, not on an incident that reproduced it.

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

**Confirmed, from MSW's own documentation:** `onUnhandledRequest` on `setupServer().listen()`
"specifies how to react to requests that are not handled by any request handlers," with
three values: `"warn"` (default — "print a warning but perform the request as-is"),
`"bypass"` ("does not print anything and perform the request as-is"), and `"error"` ("print
an error and halt request execution"). MSW docs,
`mswjs.io/docs/api/setup-server/listen/`, checked 2026-08-23.

**The rule for Layer 5 (frontend integration, mocked network — see
[01-layer-model.md](01-layer-model.md)):** set `onUnhandledRequest: 'error'` for the test
suite's MSW server, not the library default of `'warn'`. Under `'warn'`, a request that
matches no mock handler falls through and executes as a real network call — in CI, that is
either a silent failure against an unreachable host or, worse, a call that succeeds against
whatever the test happens to be able to reach, producing a test that passes for the wrong
reason. `'error'` converts a missing mock into a hard, loud test failure at the point the
gap exists, which is the failure mode this item's design is built to surface rather than
mask.

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
