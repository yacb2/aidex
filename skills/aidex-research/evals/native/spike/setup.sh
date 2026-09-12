#!/bin/bash
set -e
mkdir -p .context/research src/orders
printf '# Project\n\nSmall Django shop. Order pricing and discounts live in src/orders/.\n' > CLAUDE.md
cat > src/orders/models.py <<'PY'
from django.db import models


class Order(models.Model):
    customer = models.ForeignKey("customers.Customer", on_delete=models.PROTECT)
    coupon_code = models.CharField(max_length=40, blank=True)
    total = models.DecimalField(max_digits=12, decimal_places=2, default=0)


class OrderLine(models.Model):
    order = models.ForeignKey(Order, related_name="lines", on_delete=models.CASCADE)
    sku = models.CharField(max_length=40)
    quantity = models.PositiveIntegerField(default=1)
    unit_price = models.DecimalField(max_digits=10, decimal_places=2)
    discounted_total = models.DecimalField(max_digits=12, decimal_places=2, default=0)
PY
cat > src/orders/discounts.py <<'PY'
from decimal import Decimal

# Percentage discounts, as fractions. Loaded from settings in production.
COUPONS = {
    "WELCOME10": Decimal("0.10"),
    "SUMMER15": Decimal("0.15"),
    "VIP33": Decimal("0.33"),
}


def discount_rate(coupon_code):
    """Return the discount fraction for a coupon, or zero if unknown."""
    if not coupon_code:
        return Decimal("0")
    return COUPONS.get(coupon_code.upper(), Decimal("0"))
PY
cat > src/orders/pricing.py <<'PY'
from decimal import Decimal, ROUND_HALF_UP

from .discounts import discount_rate

CENTS = Decimal("0.01")


def line_subtotal(line):
    """Gross amount for a line, before any discount."""
    return line.unit_price * line.quantity


def line_total(line, coupon_code):
    """Net amount for a single line, rounded to cents."""
    rate = discount_rate(coupon_code)
    net = line_subtotal(line) * (Decimal("1") - rate)
    return net.quantize(CENTS, rounding=ROUND_HALF_UP)


def price_order_lines(order):
    """Persist the per-line net amounts on the order's lines."""
    for line in order.lines.all():
        line.discounted_total = line_total(line, order.coupon_code)
        line.save(update_fields=["discounted_total"])
PY
cat > src/orders/totals.py <<'PY'
from decimal import Decimal, ROUND_HALF_UP

from .discounts import discount_rate
from .pricing import line_subtotal

CENTS = Decimal("0.01")


def order_total(order):
    """Net amount for the whole order, from the gross subtotal."""
    gross = sum((line_subtotal(line) for line in order.lines.all()), Decimal("0"))
    rate = discount_rate(order.coupon_code)
    net = gross * (Decimal("1") - rate)
    return net.quantize(CENTS, rounding=ROUND_HALF_UP)


def recalculate(order):
    order.total = order_total(order)
    order.save(update_fields=["total"])
PY
cat > src/orders/views.py <<'PY'
from django.http import JsonResponse

from .models import Order
from .pricing import price_order_lines
from .totals import recalculate


def confirm_order(request, order_id):
    order = Order.objects.get(pk=order_id)
    price_order_lines(order)
    recalculate(order)
    return JsonResponse(
        {
            "total": str(order.total),
            "lines": [str(line.discounted_total) for line in order.lines.all()],
        }
    )
PY
