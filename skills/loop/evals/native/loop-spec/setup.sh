#!/bin/bash
set -e
mkdir -p src tests .context/plans .context/decisions .context/references .context/backlog .context/research .context/requests

cat > README.md <<'MD'
# cart-svc

Carrito de compras minimalista (Python, unittest).

- Código: `src/cart.py`
- Tests: `tests/test_cart.py`
- Suite: `./run_tests.sh`

Estado actual: 3 tests en rojo (descuentos, impuestos, redondeo). Arreglar uno
suele romper otro, así que la suite completa tiene que volver a correr después
de cada cambio.
MD

cat > src/cart.py <<'PY'
def subtotal(items):
    return sum(i["price"] * i["qty"] for i in items)


def discount(items, pct):
    return subtotal(items) * pct


def tax(amount, rate):
    return amount * rate


def total(items, pct=0.0, rate=0.0):
    base = subtotal(items) - discount(items, pct)
    return round(base + tax(base, rate))
PY

cat > tests/test_cart.py <<'PY'
import sys, os, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
from cart import total, discount, tax

ITEMS = [{"price": 10.0, "qty": 2}, {"price": 5.5, "qty": 1}]


class TestCart(unittest.TestCase):
    def test_discount_is_capped(self):
        self.assertEqual(discount(ITEMS, 1.5), 25.5)

    def test_tax_never_negative(self):
        self.assertEqual(tax(-10.0, 0.21), 0.0)

    def test_total_keeps_cents(self):
        self.assertEqual(total(ITEMS, 0.1, 0.21), 27.76)
PY

cat > run_tests.sh <<'SH'
#!/bin/bash
exec python3 -m unittest discover -s tests -v
SH
chmod +x run_tests.sh

cat > CLAUDE.md <<'MD'
# cart-svc

Python 3, unittest. La suite se corre con `./run_tests.sh`.
`tests/` es contrato: no se edita para hacer pasar la suite.
MD
