#!/usr/bin/env bash
# test-whole-skip-exits-2.sh — a test that skips ITSELF entirely must exit 2, not 0.
# run-all.sh counts a SKIP only on rc 2 plus a `^SKIP` line (run-all.sh:142); a whole-test
# skip that exits 0 is tallied as a PASS on a machine without node/Chrome/lsof (P4, BL-552
# recurrence). Layer: shell, one git grep pass over the files run-all.sh discovers
# (run-all.sh:81-84: .sh and .py roots, same patterns below).
#
# Whole-test skip rule, on a non-comment line:
#   .sh  an `echo`/`printf` of SKIP that carries `exit 0` itself or is followed on the very next
#        line by a bare `exit 0`.
#   .py  a `print("SKIP...` that carries, or is followed on the next line by, a bare `return`,
#        `sys.exit(0)`, `exit(0)` or `raise SystemExit(0)`.
# A partial in-run skip (the test continues afterwards) is not matched. This file is excluded:
# its own comments quote the pattern.
#
# Not duplicated here: the runtime rule for the worktree tests, which stubs docker and runs each
# test to see its rc, is skills/worktree/tests/test-exit-contracts.sh:39-50. This lint is the
# static rule over every discovered root; it does not execute any test.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"
SELF="tests/test-whole-skip-exits-2.sh"

PY='
import os, re, sys
self_path = os.environ["SELF"]
sh_exit = re.compile(r"\bexit 0\b")
py_exit = re.compile(r"\b(return|sys\.exit\(0\)|exit\(0\)|raise SystemExit\(0\))\s*$")
examined, bad = 0, []
prev = None  # (path, lineno) of the last SKIP line
for rec in sys.stdin.buffer.read().split(b"\n"):
    if rec == b"--" or not rec:
        prev = None; continue
    # git grep -z: path NUL lineno NUL text, for match and context lines alike
    parts = rec.split(b"\0", 2)
    if len(parts) != 3: continue
    path, n = parts[0].decode("utf-8", "surrogateescape"), int(parts[1])
    text = parts[2].decode("utf-8", "surrogateescape")
    if path == self_path or text.lstrip().startswith("#"):
        prev = None; continue
    py = path.endswith(".py")
    is_skip = re.search(r"print\(\s*[\"\x27]SKIP", text) if py else re.search(r"(echo|printf) +[\"\x27]?SKIP", text)
    if is_skip:
        examined += 1
        prev = (path, n)
        same = re.search(r";\s*(return|sys\.exit\(0\)|exit\(0\))\s*$", text) if py else sh_exit.search(text)
        if same:
            bad.append(f"{path}:{n}: {text.strip()}")
    elif prev and prev == (path, n - 1):
        nxt = text.strip()
        hit = py_exit.fullmatch(nxt) if py else re.match(r"exit 0\b", nxt)
        if hit:
            bad.append(f"{path}:{prev[1]}: SKIP then exit at line {n}")
        prev = None
    else:
        prev = None
print(examined)
for b in bad: print(b)
'

raw="$(mktemp)"; trap 'rm -f "$raw"' EXIT
git grep -z -nE -A1 '(echo|printf) +["'"'"']?SKIP|print\(["'"'"']SKIP' -- \
    'tests/test-*.sh' 'tests/native-eval/test-*.sh' 'skills/*/tests/test-*.sh' \
    'skills/*/scripts/test[-_]*.sh' 'hooks/test-*.sh' \
    'skills/*/tests/test_*.py' 'skills/*/scripts/test[-_]*.py' 'hooks/test-*.py' >"$raw"
grc=$?
if [[ $grc -ne 0 && $grc -ne 1 ]]; then
  echo "FAIL: git grep exited $grc — the lint could not read the tree"; exit 1
fi
res="$(SELF="$SELF" python3 -I -c "$PY" <"$raw")" \
  || { echo "FAIL: the SKIP scanner crashed"; exit 1; }
examined="$(printf '%s\n' "$res" | sed -n 1p)"
out="$(printf '%s\n' "$res" | sed 1d)"

if [[ "${examined:-0}" -eq 0 ]]; then
  echo "FAIL: examined 0 SKIP lines — the pathspecs or the pattern matched nothing"; exit 1
fi
if [[ -n "$out" ]]; then
  printf 'FAIL: whole-test SKIP exits 0 (must be exit 2):\n%s\n' "$out"
  exit 1
fi
echo "PASS: every whole-test SKIP exits 2 ($examined SKIP lines examined)"
