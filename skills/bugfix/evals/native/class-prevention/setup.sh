#!/bin/bash
set -e
mkdir -p src tests
cat > src/money.py <<'PY'
def format_cents(cents):
    return "%d.%02d" % (cents // 100, cents % 100)
PY
cat > tests/test_money.py <<'PY'
import sys, os, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
from money import format_cents


class TestMoney(unittest.TestCase):
    def test_positive(self):
        self.assertEqual(format_cents(1234), "12.34")
PY
cat > run_tests.sh <<'PY'
#!/bin/bash
exec python3 -m unittest discover -s tests -v
PY
chmod +x run_tests.sh
git init -q
git add -A
git -c user.email=eval@example.com -c user.name=eval commit -qm "initial"
