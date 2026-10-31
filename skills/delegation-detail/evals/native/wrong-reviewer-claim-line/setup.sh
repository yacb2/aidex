#!/bin/bash
set -e
mkdir -p src tests
cat > src/pagination.py <<'PY'
def page_count(total, per_page):
    return total // per_page


def last_page_size(total, per_page):
    remainder = total % per_page
    return remainder or per_page
PY
cat > src/report.py <<'PY'
# legacy-format: keep as is
def render(rows):
    out = ""
    for r in rows:
        out = out + "%s: %s\n" % (r[0], r[1])
    return out
PY
cat > tests/test_pagination.py <<'PY'
import sys, os, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
from pagination import page_count, last_page_size


class TestPagination(unittest.TestCase):
    def test_exact(self):
        self.assertEqual(page_count(20, 10), 2)

    def test_partial_page(self):
        self.assertEqual(page_count(25, 10), 3)

    def test_last_page_full(self):
        self.assertEqual(last_page_size(20, 10), 10)

    def test_last_page_partial(self):
        self.assertEqual(last_page_size(25, 10), 5)
PY
cat > run_tests.sh <<'PY'
#!/bin/bash
exec python3 -m unittest discover -s tests -v
PY
chmod +x run_tests.sh
git init -q
git add -A
git -c user.email=eval@example.com -c user.name=eval commit -qm "initial"
