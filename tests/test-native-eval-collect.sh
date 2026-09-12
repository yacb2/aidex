#!/usr/bin/env bash
# collect-cases.sh must rewrite each collected case.yaml `name:` to the
# `<skill>--<case>` folder name: `claude plugin eval --case <glob>` matches
# `name:`, not the folder, so without the rewrite `run-eval.sh --only <skill>`
# selects zero cases (measured 2026-09-12, bugfix re-run).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0
bash "$REPO/tests/native-eval/collect-cases.sh" >/dev/null || { echo "FAIL: collect-cases.sh"; exit 1; }
n=0
for y in "$REPO"/plugin-evals/*/case.yaml; do
  n=$((n+1))
  folder="$(basename "$(dirname "$y")")"
  name="$(sed -n 's/^name: *//p' "$y")"
  if [ "$name" = "$folder" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $folder has name: $name"; fi
done
[ "$n" -gt 0 ] || { echo "FAIL: zero cases collected"; exit 1; }
echo "native-eval collect: $n cases, $pass names match folder, $fail mismatched"
[ "$fail" -eq 0 ]
