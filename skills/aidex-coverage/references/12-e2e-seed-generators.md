# E2E seed generators

The deterministic data the E2E template database is built from
([11-e2e-isolation-infra.md](11-e2e-isolation-infra.md), "Template lifecycle"). Two
management commands run in order: the project's base bootstrap
(`{{seed_bootstrap_cmd}}`: catalogs, roles, base personas) and then the E2E bootstrap
(`{{seed_e2e_bootstrap_cmd}}`), which is the orchestrator for the generators below.

## `BaseGenerator` contract

Every generator subclasses the project's `BaseGenerator` and relies on exactly this
surface:

| Member | Meaning |
|---|---|
| `generate() -> {'success': bool, 'stats': {...}}` | Creates or updates the generator's rows; returns the stats dict |
| `cleanup()` | Removes the generator's rows by their natural key; optional, used only outside the template flow |
| `get_or_create_safe(Model, defaults=, **lookup)` | Idempotent create; counts into stats |
| `update_or_create_safe(Model, defaults=, **lookup)` | Idempotent upsert; counts into stats |
| `reset_stats()` / `get_stats()` | `{'created', 'updated', 'skipped', 'errors'}` |
| `self.verbose` / `self.log(msg)` | Per-row logging only under `--verbose` |

Idempotent **by natural key**: the lookup is a code, a number, an email, a tax id —
something that survives a template rebuild. Never an auto-increment id.

## The user generator

The one generator every project has: the personas the specs log in as. Password is set
on every run (idempotent), memberships are `get_or_create`.

```python
class E2EUserGenerator(BaseGenerator):
    USERS = [
        {"email": "{{persona_viewer_email}}", "password": "{{persona_password}}",
         "first_name": "E2E", "last_name": "Viewer", "role": "VIEWER", "workspace_codes": ["WS1"]},
        {"email": "{{persona_editor_email}}", "password": "{{persona_password}}",
         "first_name": "E2E", "last_name": "Editor", "role": "EDITOR", "workspace_codes": ["WS1", "WS2"]},
    ]

    def generate(self):
        self.log("=== E2E users ===")
        self.reset_stats()
        for data in self.USERS:
            user, created = self.get_or_create_safe(
                User, email=data["email"],
                defaults={"first_name": data["first_name"], "last_name": data["last_name"], "is_active": True},
            )
            user.set_password(data["password"])
            user.save(update_fields=["password"])
            for code in data["workspace_codes"]:
                ws = Workspace.objects.get(code=code)          # base bootstrap created it; a miss is a real error
                self.get_or_create_safe(WorkspaceMembership, user=user, workspace=ws,
                                        defaults={"role": data["role"]})
            if created and self.verbose:
                self.log(f"  + {data['email']}")
        stats = self.get_stats()
        return {"success": stats["errors"] == 0, "stats": stats}
```

The actual persona emails and password are facts in the profile's `personas_ref`
document; the generator is the only place they are defined in code, and the E2E
helpers' constants must match it.

## The orchestrator command

`{{seed_e2e_bootstrap_cmd}}` runs each generator in dependency order and prints one
line per result. It is safe to run twice; the template flow runs it exactly once.

```python
class Command(BaseCommand):
    help = "Bootstrap E2E test data (idempotent). Runs after the base bootstrap."

    def add_arguments(self, parser):
        parser.add_argument("--verbose", action="store_true")

    def handle(self, *args, **options):
        verbose = options["verbose"]
        # Dependency order: config/catalogs -> entities -> relationships -> users
        for n, gen_cls in enumerate([E2EConfigGenerator, E2ESupplierGenerator,
                                     E2EInvoiceGenerator, E2EPaymentGenerator, E2EUserGenerator], 1):
            self.stdout.write(self.style.NOTICE(f"{n}. {gen_cls.__name__}"))
            result = gen_cls(verbose=verbose).generate()
            stats = result["stats"]
            style = self.style.SUCCESS if result["success"] else self.style.ERROR
            self.stdout.write(style(f"   {stats['created']} created, {stats['updated']} updated, "
                                    f"{stats['skipped']} skipped, {stats['errors']} errors"))
```

A generator is registered in the package `__init__.py` and appended to this list at
the position its foreign keys require. Signals fire during generation: a payment
generator that runs before the invoice generator has nothing to update.

## The six rules

1. **Idempotent.** Only `get_or_create_safe` / `update_or_create_safe`; never bare
   `create()`.
2. **`E2E`-prefixed.** Every code, name, number and reference starts with `E2E` or
   `E2E-`; it is how the verification query in 11's checklist can prove the dev
   database is clean.
3. **Natural-key lookup.** Code, number, email, tax id — never id.
4. **Dependency order.** Config, then entities, then relationships, then users.
5. **Verbose-gated logging.** Per-row output only under `self.verbose`; the summary
   line always.
6. **Stats dict returned.** `{'success', 'stats': {'created','updated','skipped','errors'}}`,
   and `success` is `errors == 0`.

## When to rebuild the template

`./test-e2e.sh --setup-template` after any of: a new or edited generator, a change to
the base bootstrap, a migration. A spec that asserts on a seeded amount and starts
failing after a calculation change is telling you the generator's expected values are
now stale: update the generator, rebuild, then fix the assertion — in that order.

The seeded scenarios themselves (which invoices, which statuses, which workspaces) are
project data and belong in the project's own `.context/references/` (the profile's
`personas_ref` points at the persona table; a sibling document covers the rest). This
skill carries the pattern, never the inventory.
