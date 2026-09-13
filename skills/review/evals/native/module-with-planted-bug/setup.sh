#!/bin/bash
set -e
mkdir -p src/pricing .context/backlog .context/audits
printf '# shop-api\n\nSmall Python order-pricing service.\n' > CLAUDE.md

cat > src/pricing/__init__.py <<'PY'
from .totals import order_total

__all__ = ["order_total"]
PY

cat > src/pricing/cart.py <<'PY'
"""Cart lines and their subtotal."""


class Line:
    def __init__(self, sku, unit_price_cents, quantity):
        self.sku = sku
        self.unit_price_cents = unit_price_cents
        self.quantity = quantity

    def total_cents(self):
        return self.unit_price_cents * self.quantity


def subtotal_cents(lines):
    return sum(line.total_cents() for line in lines)


def legacy_format_money(cents, symbol="$"):
    """Formats cents as money. Superseded by the reporting service."""
    whole, rest = divmod(abs(cents), 100)
    sign = "-" if cents < 0 else ""
    return "%s%s%d.%02d" % (sign, symbol, whole, rest)
PY

cat > src/pricing/discounts.py <<'PY'
"""Coupon discounts. Percentages arrive as whole numbers (10 means 10%)."""


class Coupon:
    def __init__(self, code, percent_off):
        self.code = code
        self.percent_off = percent_off


def discount_cents(subtotal, coupon):
    if coupon is None:
        return 0
    return int(subtotal * coupon.percent_off)


def is_applicable(subtotal, coupon):
    return coupon is not None and subtotal > 0
PY

cat > src/pricing/totals.py <<'PY'
"""Order total: subtotal, coupon discount, then tax."""

from .cart import subtotal_cents
from .discounts import discount_cents, is_applicable

TAX_RATE = 0.21


def order_total(lines, coupon=None):
    subtotal = subtotal_cents(lines)
    discount = discount_cents(subtotal, coupon) if is_applicable(subtotal, coupon) else 0
    taxable = subtotal - discount
    return taxable + int(taxable * TAX_RATE)
PY
