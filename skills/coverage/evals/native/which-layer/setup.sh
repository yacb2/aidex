#!/bin/bash
set -e
mkdir -p billing/tests .context

printf '# quotes-api\n\nPlain Django-shaped billing service. Tests run with pytest.\n' > CLAUDE.md

cat > billing/services.py <<'PY'
TAX_RATE = 0.21
ANNUAL_DISCOUNT = 0.10


def quote_total(subtotal, plan):
    """Total for a quote. Annual plans discount BEFORE tax."""
    if plan == "annual":
        subtotal = subtotal * (1 - ANNUAL_DISCOUNT)
        return round(subtotal * (1 + TAX_RATE), 2)
    return round(subtotal * (1 + TAX_RATE), 2)
PY

cat > billing/views.py <<'PY'
from django.http import JsonResponse

from .services import quote_total


def quote(request):
    subtotal = float(request.GET.get("subtotal", 0))
    plan = request.GET.get("plan", "monthly")
    return JsonResponse({"total": quote_total(subtotal, plan)})
PY

touch billing/__init__.py billing/tests/__init__.py

cat > billing/tests/test_monthly_quote.py <<'PY'
from billing.services import quote_total


def test_monthly_total_adds_tax():
    assert quote_total(100.0, "monthly") == 121.0
PY

cat > .context/testing-profile.md <<'MD'
---
title: Testing profile
status: open
created: 2026-09-13
updated: 2026-09-13
# core — every project
project_slug: quotes_api
project_kebab: quotes-api
blindspot_expansions:
  - a migration => every app referencing the changed model
module_map:
testing_packs:

# no pack: the whole test surface is one suite
suite_cmd: pytest
---

# Testing profile

This file is a DELTA over the testing canon. Facts about this project only.
MD
