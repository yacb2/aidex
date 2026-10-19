#!/usr/bin/env bash
# test-cross-numbers.sh — BL-852: rubric line 7 cross-number WARNs are deterministic
# and have no false positive on the cases a human accepts.
#
# Two rules (check-artifact WARN, never FAIL): cross-number-chart (a chart value
# against the same-kind cells of its table row) and table-header-unit (a time or
# money column of bare numbers needs a unit in its header). A prose rule was
# built and removed (unsound: `(84%)`, years, a figure given to the wrong row).
# Layer: the rules are pure functions of markup (cross_numbers.findings), so the
# table of cases runs there; three built fixtures then prove the wiring through
# spec_build.py + check-artifact (the chart marks are the kit's own, never hand-typed).
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD="$SKILL/scripts/spec_build.py"
CHECK="$SKILL/scripts/check-artifact.sh"
FX="$SKILL/tests/fixtures/cross-numbers"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf 'ok   — %s\n' "$*"; }

# --- pure-function table -----------------------------------------------------
python3 -I - "$SKILL/scripts/dash" <<'PY' || failures=$((failures + 1))
import sys
sys.path.insert(0, sys.argv[1])
import cross_numbers as cn

def table(head, rows):
    h = "".join(f"<th>{c}</th>" for c in head)
    b = "".join("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>" for r in rows)
    return f"<table><thead><tr>{h}</tr></thead><tbody>{b}</tbody></table>"

def chart(marks, pct=False, tick=None):
    t = "".join(f"<rect><title>{l}: {v}</title></rect>" for l, v in marks)
    tick = tick or ("<text>80 %</text>" if pct else "<text>80</text>")
    return f'<figure class="chart"><svg>{tick}{t}</svg></figure>'

def slugs(markup):
    return [s for s, _ in cn.findings(markup)]

def unit(header, cells, extra=()):
    return table(["Run", header], [["a", cells[0]], ["b", cells[1]], *extra])

# (name, markup, expected slugs)
cases = [
    # header: the unit words and marks all satisfy the rule
    *[(f"unit '{h}' passes", unit(h, ("12", "30")), []) for h in (
        "Wait (s)", "Wait [ms]", "Wait s", "Wait ms", "Wait min", "Wait h", "Wait hrs",
        "Cost USD", "Cost EUR", "Cost $", "Wait %", "Cost/run",
        "Tiempo seg", "Espera dias", "Espera días", "Tiempo horas", "Wait days",
        "Latency seconds", "Delay minutes", "Duration weeks", "Costo usd")],
    # header: a time or money measure with no unit is flagged
    *[(f"no unit '{h}' flagged", unit(h, ("12", "30")), ["table-header-unit"]) for h in (
        "Wait time", "Tiempo de espera", "Latency", "Cost", "Precio", "p95", "Duration",
        "Builder's wait time", "Builder’s wait time", "Gasto",
        "Cost tokens", "Time to first token", "Coste por token")],
    # header: counts, sizes, rates and identifiers are not judged
    *[(f"'{h}' bare numbers pass", unit(h, ("32", "64")), []) for h in (
        "Batch size", "Hit rate", "Riesgo alto", "Count", "Ronda", "Files", "Largo", "Peso")],
    # header boundaries
    ("one number cell is not a column", table(["Run", "Wait time"], [["a", "12"], ["b", "n/a"]]), []),
    ("empty markers are ignored, two numbers still count",
     table(["Run", "Wait time"], [["a", "12"], ["b", "-"], ["c", "30"]]), ["table-header-unit"]),
    ("a cell with its own unit is not bare",
     table(["Run", "Wait time"], [["a", "12 s"], ["b", "30 s"]]), []),
    ("one text cell makes the column not bare",
     table(["Run", "Wait time"], [["a", "12"], ["b", "slow"]]), []),
    ("the first column is a label, never judged",
     table(["Wait time", "Run"], [["12", "a"], ["30", "b"]]), []),
    ("colspan table is skipped",
     table(["Run", "Wait time"], [["a", "12"], ["b", "30"]]).replace("<th>", "<th colspan=\"1\">"), []),
    # chart vs table
    ("chart agrees", chart([("Otras skills", 1690)]) + table(["Skill", "Tokens (miles)"], [["Otras skills", "1690"]]), []),
    ("chart differs", chart([("Otras skills", 1690)]) + table(["Skill", "Tokens (miles)"], [["Otras skills", "4930"]]),
     ["cross-number-chart"]),
    ("chart matches any numeric cell of the row",
     chart([("Otras skills", 320)]) + table(["Skill", "A", "B"], [["Otras skills", "1690", "320"]]), []),
    ("label match ignores case and accents",
     chart([("TOKENS", 5)]) + table(["Skill", "N"], [["Tókens", "6"]]), ["cross-number-chart"]),
    ("chart label with no table row says nothing", chart([("Otras", 1)]) + table(["S", "N"], [["Backlog", "9"]]), []),
    ("table row with no numeric cell says nothing", chart([("Backlog", 1)]) + table(["S", "N"], [["Backlog", "n/a"]]), []),
    ("share chart beside an absolute table is two measures",
     chart([("Otras skills", 84), ("Backlog", 16)], pct=True)
     + table(["Skill", "Tokens (miles)"], [["Otras skills", "1690"], ["Backlog", "320"]]), []),
    ("a percent chart is checked against percent cells",
     chart([("Otras skills", 84)], pct=True) + table(["Skill", "Share"], [["Otras skills", "85%"]]),
     ["cross-number-chart"]),
    ("a percent chart agreeing with percent cells passes",
     chart([("Otras skills", 84)], pct=True) + table(["Skill", "Share"], [["Otras skills", "84%"]]), []),
    ("prose figures are not read (the removed rule): (84%), a count, a year",
     "<p>Otras skills (84%) y Otras skills (12), Otras skills (2025) y Backlog 1690, el menor.</p>"
     + table(["Skill", "Tokens (miles)"], [["Otras skills", "1690"], ["Backlog", "320"]]), []),
    ("the echo_lab sentence is not read",
     "<p>713 of 1519 voiced segments (46.9%) were kept.</p>" + table(["K", "N"], [["Voiced segments", "1519"], ["Kept", "713"]]), []),
    # rounding: half away from zero, to the fewer decimals
    ("12.5 in the table, 13 in the chart (half up)",
     chart([("Otras skills", 13)]) + table(["S", "N"], [["Otras skills", "12.5"]]), []),
    ("12.5 in the table, 12 in the chart: the kit's own float round() prints 12",
     chart([("Otras skills", 12)]) + table(["S", "N"], [["Otras skills", "12.5"]]), []),
    ("12.5 in the table, 14 in the chart differs",
     chart([("Otras skills", 14)]) + table(["S", "N"], [["Otras skills", "12.5"]]), ["cross-number-chart"]),
    # the kit prints round(float, d): 1.125 -> 1,12; 12.125 -> 12,12; 2.675 -> 2,67
    *[(f"kit float rounding {v} -> {k}: coherent chart stays quiet",
       chart([("Corrida A", k)]) + table(["S", "N"], [["Corrida A", v]]), [])
      for v, k in (("1.125", "1.12"), ("12.125", "12.12"), ("2.675", "2.67"))],
    # a cell too big for Decimal never raises into the build
    ("a 32-digit id cell does not crash, chart value matches elsewhere in the row",
     chart([("Otras skills", 5)]) + table(["S", "Id", "N"], [["Otras skills", "12345678901234567890123456789012", "5"]]), []),
    ("a 32-digit id cell does not crash, mismatch still WARNs",
     chart([("Otras skills", 7)]) + table(["S", "Id", "N"], [["Otras skills", "12345678901234567890123456789012", "5"]]),
     ["cross-number-chart"]),
    ("a 400-digit (inf) cell does not crash",
     chart([("Otras skills", 5)]) + table(["S", "Id"], [["Otras skills", "9" * 400]]), ["cross-number-chart"]),
    # percent ticks: `%` right after the number, anything after it
    ("share chart whose unit is '% del total' beside an absolute table",
     chart([("Otras skills", 84)], tick="<text>80 % del total</text>")
     + table(["Skill", "Tokens (miles)"], [["Otras skills", "1690"]]), []),
    ("a tick that merely mentions % later is not percent",
     chart([("Otras skills", 84)], tick="<text>80 pts (de 100 %)</text>")
     + table(["Skill", "Tokens (miles)"], [["Otras skills", "1690"]]), ["cross-number-chart"]),
    ("13.5 in the table, 14 in the chart", chart([("Otras skills", 14)]) + table(["S", "N"], [["Otras skills", "13.5"]]), []),
    ("negative -12.5 against -13 (away from zero)",
     chart([("Otras skills", "-13")]) + table(["S", "N"], [["Otras skills", "-12.5"]]), []),
    ("12.34 against 12.3 compares at one decimal",
     chart([("Otras skills", "12.3")]) + table(["S", "N"], [["Otras skills", "12.34"]]), []),
    ("12.36 against 12.3 differs at one decimal",
     chart([("Otras skills", "12.3")]) + table(["S", "N"], [["Otras skills", "12.36"]]), ["cross-number-chart"]),
    ("thousands separator: 1,690 against 1690",
     chart([("Otras skills", "1,690")]) + table(["S", "N"], [["Otras skills", "1690"]]), []),
]
bad = 0
for name, markup, want in cases:
    got = slugs(markup)
    if got != want:
        bad += 1
        print(f"FAIL: {name}: wanted {want}, got {got}")
# the message quotes the chart's own printed value, never scientific notation
msg = cn.findings(chart([("Otras skills", "18230000")])
                  + table(["S", "N"], [["Otras skills", "5"]]))
if not (msg and "18230000" in msg[0][1] and "e+" not in msg[0][1]):
    bad += 1
    print(f"FAIL: the message must print the chart value as written: {msg}")
if bad:
    sys.exit(1)
print(f"ok   — {len(cases) + 1} cross_numbers cases")
PY

# --- wiring through the real build + check -----------------------------------
build() { python3 "$BUILD" "$FX/$1.spec.md" -o "$TMP/$1.html" </dev/null 2>&1; }

out="$(build good)"; rc=$?
[[ $rc -eq 0 && "$out" != *cross-number* && "$out" != *table-header-unit* ]] \
  && ok "agreeing table, chart and unit header build with no cross-number warning" \
  || fail "good.spec.md (rc=$rc): $out"

out="$(build share-vs-absolute)"; rc=$?
[[ $rc -eq 0 && "$out" != *cross-number* ]] \
  && ok "a share chart beside an absolute table builds clean" \
  || fail "share-vs-absolute (rc=$rc): $out"

out="$(build chart-vs-table)"; rc=$?
[[ $rc -eq 0 && "$out" == *"WARN [cross-number-chart]"* && "$out" == *"1690"* && "$out" != *"FAIL"* ]] \
  && ok "a chart value the table row does not carry WARNS and does not refuse the build" \
  || fail "chart-vs-table (rc=$rc): $out"

out="$(build header-unit)"; rc=$?
[[ $rc -eq 0 && "$out" == *"WARN [table-header-unit]"* && "$out" == *"Tiempo de espera"* ]] \
  && ok "a time column with no unit WARNS and does not refuse the build" \
  || fail "header-unit (rc=$rc): $out"

[[ $failures -eq 0 ]] && { echo "test-cross-numbers: all passed"; exit 0; }
echo "test-cross-numbers: $failures failed"; exit 1
