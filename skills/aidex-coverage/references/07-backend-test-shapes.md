# Backend test shapes (layers 1–2)

The canonical forms for Django + DRF tests under pytest-django. Which layer a test
belongs in is decided by [01-layer-model.md](01-layer-model.md); when shared setup
becomes a fixture is decided by [03-fixtures-convention.md](03-fixtures-convention.md).
This file only carries the shapes themselves — one example per pattern.

## Layout and naming

One `tests/` package per app; a large app splits it into one sub-package per model
with the same three files inside.

```text
backend/apps/<app>/tests/
  conftest.py           # app-specific fixtures (the global set is in the project root conftest)
  factories.py          # factory_boy factories
  test_models.py        # layer 1: model methods, managers, signals
  test_serializers.py   # layer 1: validation and representation
  test_views.py         # layer 2: HTTP requests through APIClient
```

| Thing | Form |
|---|---|
| Test file | `test_models.py`, `test_serializers.py`, `test_views.py` |
| Test class | `TestInvoice`, `TestInvoiceAPI`, `TestInvoiceWorkspaceIsolation` |
| Test method | `test_<what>_<expected>`: `test_unauthenticated_returns_401` |
| Factory | `InvoiceFactory` in `factories.py` |
| Marker | every DB-touching class carries `@pytest.mark.django_db` |

## The fixture set (root `conftest.py`)

Four fixtures compose into an authenticated, workspace-scoped client; a test that
rebuilds this chain by hand is the rule-of-three trigger.

```python
@pytest.fixture
def api_client():
    return APIClient()                       # unauthenticated

@pytest.fixture
def workspace():
    return WorkspaceFactory()

@pytest.fixture
def user(workspace):
    user = UserFactory()
    WorkspaceMembershipFactory(user=user, workspace=workspace)
    return user

@pytest.fixture
def authenticated_client(api_client, user):
    api_client.force_authenticate(user=user)  # no login round-trip; the test is about the view, not auth
    return api_client
```

## Factories

`Sequence` for anything unique (a hardcoded unique value breaks at the second
`create_batch`), `SubFactory` for every FK.

```python
class InvoiceFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = Invoice

    number = factory.Sequence(lambda n: f"INV-{n:04d}")
    workspace = factory.SubFactory(WorkspaceFactory)
```

## Layer 1 shapes

**Model label.** `__str__` delegates to `get_label()`: test the label once, the delegation once.

```python
def test_get_label(self):
    assert InvoiceFactory(number="INV-1", name="Alpha").get_label() == "INV-1 - Alpha"

def test_str_delegates_to_get_label(self):
    inv = InvoiceFactory()
    assert str(inv) == inv.get_label()
```

**Soft delete.** The row survives, the flag flips; assert on the DB, not the instance.

```python
def test_delete_is_soft(self):
    inv = InvoiceFactory()
    inv.delete()
    assert Invoice.all_objects.get(pk=inv.pk).is_deleted is True
```

**Signal.** Create the trigger, refresh the receiver, assert the derived value.

```python
def test_payment_updates_invoice_outstanding(self):
    inv = InvoiceFactory(total=Decimal("100.00"))
    PaymentFactory(invoice=inv, amount=Decimal("50.00"), status="COMPLETED")
    inv.refresh_from_db()
    assert inv.outstanding_amount == Decimal("50.00")
```

**Time.** `freezegun` pins `now()`; never compare against a `date.today()` computed in the test.

```python
@freeze_time("2026-01-15 10:00:00")
def test_created_at_is_frozen_now(self):
    assert InvoiceFactory().created_at.date() == date(2026, 1, 15)
```

## Layer 2 shapes

The four assertions every workspace-scoped endpoint owes:

```python
@pytest.mark.django_db
class TestInvoiceAPI:
    def test_unauthenticated_returns_401(self, api_client):
        assert api_client.get("/api/v1/invoices/").status_code == 401

    def test_list_is_workspace_scoped(self, authenticated_client, workspace):
        InvoiceFactory.create_batch(3, workspace=workspace)
        InvoiceFactory()                                   # another workspace
        resp = authenticated_client.get("/api/v1/invoices/")
        assert resp.data["count"] == 3

    def test_cross_workspace_retrieve_returns_404(self, authenticated_client):
        other = InvoiceFactory()                           # not the user's workspace
        resp = authenticated_client.get(f"/api/v1/invoices/{other.uuid}/")
        assert resp.status_code == 404                     # 404, never 403: a 403 confirms the row exists

    def test_filter_by_status(self, authenticated_client, workspace):
        InvoiceFactory(workspace=workspace, status="active")
        InvoiceFactory(workspace=workspace, status="inactive")
        resp = authenticated_client.get("/api/v1/invoices/?status=active")
        assert resp.data["count"] == 1
```

**Dropdown endpoints** return a bare, unpaginated list of `{id, label}` and nothing
else — one test asserts the shape, one asserts the absence of pagination:

```python
def test_dropdown_shape(self, authenticated_client, workspace):
    InvoiceFactory(workspace=workspace)
    resp = authenticated_client.get("/api/v1/invoices/dropdown/")
    assert isinstance(resp.data, list)                     # not {"count", "results"}
    assert set(resp.data[0]) == {"id", "label"}
```

The run command is a profile fact (`backend_test_cmd`,
[14-testing-profile.md](14-testing-profile.md)); one test is `<file>::<Class>::<method>`.
