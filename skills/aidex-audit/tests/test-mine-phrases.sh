#!/usr/bin/env bash
# test-mine-phrases.sh — pins the one decision mine_phrases.py makes.
#
# The instrument exists to surface a recurring HABIT with no category list
# supplied, and the only thing standing between it and a list of whatever the
# corpus happened to argue about most is the ranking key: dispersion across
# sessions, not raw frequency.
#
# A long argument about invoices produces a phrase forty times in one session.
# An instruction the person repeats produces it once in forty sessions. Ranked by
# frequency the first buries the second, and the instrument returns topics
# instead of habits — which is the failure the whole open-discovery pass exists
# to avoid.
#
# Run with: bash skills/aidex-audit/tests/test-mine-phrases.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MINER="$HERE/../scripts/usage-retro/mine_phrases.py"

PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run_miner <label> <args...> — sets `out` and FAILS if the miner did not actually
# run. Every negative assertion below ("phrase X is absent") is satisfied by empty
# output, so without this a miner that CRASHED passed them: verified by inserting
# one plausible edit at the natural empty-result boundary
# (`max(len(k) for ... in kept)`), which raises ValueError on the all-stopword
# dataset and exits 1 with zero stdout — and the suite reported 4 passed, 0 failed
# against it. Absence of a phrase is only evidence when the instrument spoke.
run_miner() {
  local label="$1"; shift
  local err="$TMP/err.$$"
  out="$(python3 "$MINER" "$@" 2>"$err")"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    bad "$label: the miner exited $rc — $(tr '\n' ' ' < "$err" | tail -c 200)"
    return 1
  fi
  if ! grep -q 'phrase' <<<"$out"; then
    bad "$label: the miner produced no header, so it did not report anything"
    return 1
  fi
  ok "$label: the miner ran and reported"
  return 0
}

# Two sessions shouting a topic 40 times, ten sessions each saying a habit once.
python3 - "$TMP/d.jsonl" <<'PY'
import json, sys
recs = []
# Spread over TWO sessions on purpose: with the topic confined to one session it
# is excluded by --min-sessions and the ranking comparison below never happens —
# the assertion passes for the wrong reason. It has to clear the same bar and
# still lose.
for i in range(40):
    recs.append({"session": "loud" if i % 2 else "loud2", "project": "p1",
                 "ts": f"2026-01-01T00:{i:02d}:00",
                 "prompt": "revisa la conciliacion bancaria del albaran otra vez"})
for i in range(10):
    recs.append({"session": f"s{i}", "project": f"p{i%4}", "ts": f"2026-01-02T00:{i:02d}:00",
                 "prompt": "no te detengas hasta que termines todo el trabajo"})
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    for r in recs:
        fh.write(json.dumps(r, ensure_ascii=False) + "\n")
PY

run_miner "ranking dataset" --dataset "$TMP/d.jsonl" --min-n 3 --max-n 5 \
          --top 40 --min-sessions 2

habit_line="$(grep -n 'no te detengas' <<<"$out" | head -1 | cut -d: -f1)"
topic_line="$(grep -n 'conciliacion bancaria' <<<"$out" | head -1 | cut -d: -f1)"

[[ -n "$habit_line" ]] && ok "the habit repeated across sessions is reported" \
                       || bad "the cross-session habit never appeared: $out"
if [[ -n "$habit_line" && -n "$topic_line" ]]; then
  [[ "$habit_line" -lt "$topic_line" ]] \
    && ok "dispersion outranks frequency (habit above a 4x more frequent topic)" \
    || bad "the 40-hit two-session topic outranked the 10-session habit"
else
  bad "the topic phrase is missing, so the ranking comparison did not run: $out"
fi

# A phrase confined to two sessions is not a habit, whatever its count.
if run_miner "min-sessions 3" --dataset "$TMP/d.jsonl" --min-n 3 --max-n 5 \
             --top 40 --min-sessions 3; then
  grep -q 'conciliacion bancaria' <<<"$out" \
    && bad "a phrase living in two sessions survived --min-sessions 3" \
    || ok "--min-sessions excludes a low-dispersion phrase regardless of its count"
fi

# Function words alone are not a finding; without this the top of the list is
# "por lo tanto" and the instrument is unreadable.
python3 - "$TMP/stop.jsonl" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    for i in range(8):
        fh.write(json.dumps({"session": f"s{i}", "project": "p", "ts": "2026-01-01T00:00:00",
                             "prompt": "de la que se lo de la que"}, ensure_ascii=False) + "\n")
PY
if run_miner "all-stopword dataset" --dataset "$TMP/stop.jsonl" --min-n 3 --max-n 5 \
             --top 20 --min-sessions 2; then
  [[ "$(grep -c 'de la que' <<<"$out")" -eq 0 ]] \
    && ok "an all-stopword phrase is not reported" || bad "stopword-only n-grams reached the output"
fi

echo
echo "mine_phrases: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
