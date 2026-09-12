#!/bin/bash
set -e
mkdir -p src tests
cat > src/clamp.py <<'PY'
def clamp(value, low, high):
    if value < low:
        return low
    if value > high:
        return value
    return value
PY
cat > tests/test_clamp.py <<'PY'
import sys, os, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
from clamp import clamp


class TestClamp(unittest.TestCase):
    def test_below_low(self):
        self.assertEqual(clamp(-1, 0, 10), 0)
PY
cat > run_tests.sh <<'PY'
#!/bin/bash
exec python3 -m unittest discover -s tests -v
PY
chmod +x run_tests.sh
