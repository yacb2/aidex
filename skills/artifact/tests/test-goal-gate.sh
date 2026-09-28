#!/usr/bin/env bash
# The goal gate's own test: the seven-line shape, the exit rule, the naming rule
# and every escape detector — including the two that cannot fire on today's
# grammar and would otherwise ship as dead checks nobody has ever seen pass.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
ok() { echo "  ok: $1"; }
bad() { echo "FAIL: $1"; fails=$((fails + 1)); }
check() { if [ "$2" = "1" ]; then ok "$1"; else bad "$1${3:+: $3}"; fi; }

# Two corpora. The REAL one is built from the owner's private pages and does
# not ship: it is wherever AIDEX_SPEC_CORPUS points, and a case that asserts a
# fact about IT prints `SKIP <case>` when the variable is unset — it never
# passes in silence. Every case about the gate's LOGIC runs on a synthetic
# corpus (mini_corpus.py, from fixtures/mini-corpus/), so it runs on any clone.
REAL="${AIDEX_SPEC_CORPUS:-}"
skip() { echo "SKIP $1: AIDEX_SPEC_CORPUS not set"; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
MINI="$tmp/mini"
python3 "$HERE/mini_corpus.py" "$MINI" >/dev/null \
  || { echo "FAIL: could not lay out the synthetic corpus"; exit 1; }

echo "== without a corpus the gate measures nothing, and says so =="
mkdir -p "$tmp/empty"
: > "$tmp/afile"
# Every required path gets its own partial corpus: a guard that stopped asking
# for one of them would let the gate print `blind: 0/3` or run with no floor.
PARTS="corpus-sample.json baseline.json corpus-specs/GATE-FLOOR.json blind-trial-log.md figure-census.md corpus-specs"
for part in $PARTS; do
  d="$tmp/partial-$(printf '%s' "$part" | tr '/.' '__')"
  cp -R "$MINI" "$d"
  rm -r "$d/$part"
done
for label in unset empty afile $PARTS; do
  case "$label" in
    unset) out="$(env -u AIDEX_SPEC_CORPUS bash "$HERE/goal-gate.sh" --no-contract 2>"$tmp/err")"; rc=$? ;;
    empty) out="$(AIDEX_SPEC_CORPUS="$tmp/empty" bash "$HERE/goal-gate.sh" --no-contract 2>"$tmp/err")"; rc=$? ;;
    afile) out="$(AIDEX_SPEC_CORPUS="$tmp/afile" bash "$HERE/goal-gate.sh" --no-contract 2>"$tmp/err")"; rc=$? ;;
    *)     out="$(AIDEX_SPEC_CORPUS="$tmp/partial-$(printf '%s' "$label" | tr '/.' '__')" bash "$HERE/goal-gate.sh" --no-contract 2>"$tmp/err")"; rc=$? ;;
  esac
  err="$(cat "$tmp/err")"
  check "[$label] exits 2" "$([ $rc -eq 2 ] && echo 1 || echo 0)" "exit $rc"
  check "[$label] prints no gate line at all" "$([ -z "$out" ] && echo 1 || echo 0)" "$out"
  check "[$label] says why, in one line naming AIDEX_SPEC_CORPUS" \
    "$([ "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" -eq 1 ] \
       && printf '%s' "$err" | grep -q 'AIDEX_SPEC_CORPUS' && echo 1 || echo 0)" "$err"
  case "$label" in
    unset|empty) ;;
    afile) check "[afile] says it is not a directory" \
             "$(printf '%s' "$err" | grep -q 'is not a directory' && echo 1 || echo 0)" "$err" ;;
    *) check "[$label] names the path it lacks" \
         "$(printf '%s' "$err" | grep -qF "lacks $label" && echo 1 || echo 0)" "$err" ;;
  esac
done

# The shape and the exit rule, end to end through goal-gate.sh on one corpus.
# `out` is left set for the caller's corpus-specific checks.
seven_lines() {
  local label="$1" dir="$2" rc n i want got full rcf want_rc
  out="$(AIDEX_SPEC_CORPUS="$dir" bash "$HERE/goal-gate.sh" --no-contract 2>/dev/null)"
  rc=$?
  # `newly-fail:` is blocking, and --no-contract does not measure it: an
  # unmeasured blocking line must fail the run, never read as a pass.
  check "[$label] --no-contract exits 1: newly-fail blocks and was not measured" \
    "$([ $rc -eq 1 ] && echo 1 || echo 0)" "exit $rc"
  # `mapfile` is bash 4; this repo's suite runs on macOS's bash 3.2, where an
  # array read is the one shape that is portable.
  n=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  check "[$label] exactly seven lines" "$([ "$n" -eq 7 ] && echo 1 || echo 0)" "got $n: $out"
  i=1
  for want in corpus escapes blind figures newly-fail ladder baseline; do
    got="$(printf '%s\n' "$out" | sed -n "${i}p")"
    check "[$label] line $i is \`$want:\`" \
      "$([ "${got%%:*}" = "$want" ] && echo 1 || echo 0)" "got '$got'"
    i=$((i + 1))
  done
  check "[$label] no \`diagrams:\` line — it is retired into \`figures:\`" \
    "$(printf '%s\n' "$out" | grep -q '^diagrams:' && echo 0 || echo 1)" "$out"
  check "[$label] blind is counted from the blind-trial log, not stubbed" \
    "$(printf '%s\n' "$out" | grep -qx 'blind: 3/3' && echo 1 || echo 0)" "$out"
  check "[$label] figures is counted from the figure census, not stubbed" \
    "$(printf '%s\n' "$out" | grep -qE '^figures: [0-9]+/[1-9][0-9]*$' && echo 1 || echo 0)" "$out"
  check "[$label] newly-fail reads unknown when the contract was not measured" \
    "$(printf '%s\n' "$out" | grep -qx 'newly-fail: unknown' && echo 1 || echo 0)" "$out"
  check "[$label] the ladder counts every figure of the census, once" \
    "$(printf '%s\n' "$out" | awk -F'[ /]' '
        /^figures:/ { total = $3 }
        /^ladder:/  { sum = $3 + $6 + $9; ok = ($0 ~ /^ladder: r1 [0-9]+ · r2 [0-9]+ · r3 [0-9]+$/) }
        END { print (ok && sum == total) ? 1 : 0 }')" "$out"
  check "[$label] baseline is non-empty" \
    "$(printf '%s\n' "$out" | grep -qE '^baseline: .+' && echo 1 || echo 0)" "$out"

  # The count `corpus:` is blind to: a build that keeps every word of a page and
  # loses the structure the contract is about reads as clean to the judge. It was
  # invisible until 2026-09-24, when 12 of the 30 converted pages were building
  # into pages that fail check-artifact while their originals pass.
  full="$(AIDEX_SPEC_CORPUS="$dir" bash "$HERE/goal-gate.sh" 2>/dev/null)"
  rcf=$?
  check "[$label] newly-fail is a number once the contract is measured" \
    "$(printf '%s\n' "$full" | grep -qE '^newly-fail: [0-9]+$' && echo 1 || echo 0)" "$full"
  check "[$label] baseline repeats the count from the same contract run" \
    "$(printf '%s\n' "$full" | awk '
        /^newly-fail:/ { n = $2 }
        /^baseline:/   { if (match($0, / [0-9]+ newly fail \(source passed, build fails\)$/)) b = substr($0, RSTART + 1) + 0; else b = -1 }
        END { print (n != "" && n + 0 == b) ? 1 : 0 }')" "$full"
  # Blocking means the exit status follows the two lines: 0 only when every
  # figure is carried or waived by name in the census (a waived figure is one
  # the census records as not carried) and no page newly fails (corpus and
  # escapes held).
  local waived fc ft
  waived=$(grep -cE '^page=.* waived=[a-z-]+$' "$dir/figure-census.md" 2>/dev/null)
  fc=$(printf '%s\n' "$full" | sed -n 's/^figures: \([0-9]*\)\/[0-9]*$/\1/p')
  ft=$(printf '%s\n' "$full" | sed -n 's/^figures: [0-9]*\/\([0-9]*\)$/\1/p')
  if [ -n "$fc" ] && [ -n "$ft" ] && [ $((fc + ${waived:-0})) -eq "$ft" ] \
     && printf '%s\n' "$full" | grep -qx 'newly-fail: 0'; then want_rc=0; else want_rc=1; fi
  check "[$label] the contract run exits $want_rc, as its figures/newly-fail lines say" \
    "$([ $rcf -eq $want_rc ] && echo 1 || echo 0)" "exit $rcf: $full"
  out_full="$full"
}

echo
echo "== the seven lines, in the fixed order =="
seven_lines synthetic "$MINI"
check "[synthetic] every page of the synthetic corpus builds back to itself" \
  "$(printf '%s\n' "$out" | grep -qx 'corpus: 3/3' && echo 1 || echo 0)" "$out"
check "[synthetic] every synthetic figure is carried, and the gate is green" \
  "$(printf '%s\n' "$out_full" | grep -qx 'figures: 4/4' \
     && printf '%s\n' "$out_full" | grep -qx 'newly-fail: 0' && echo 1 || echo 0)" "$out_full"
if [ -n "$REAL" ]; then
  seven_lines corpus "$REAL"
  check "[corpus] corpus counts against the frozen 30" \
    "$(printf '%s\n' "$out" | grep -qE '^corpus: [0-9]+/30$' && echo 1 || echo 0)" "$out"
  check "[corpus] figures counts against the census's 45" \
    "$(printf '%s\n' "$out" | grep -qE '^figures: [0-9]+/45$' && echo 1 || echo 0)" "$out"
else
  skip "the seven lines on the real corpus"
fi

echo
echo "== the naming rule maps every sampled page to a distinct spec =="
python3 - "$HERE" "$REAL" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1])
import goal_gate as g
assert g.spec_name("proj_ws/.context/reports/a-b.html") == "proj_ws__a-b.spec.md"
# The collision the project prefix exists for: same basename, two projects.
assert g.spec_name("x_ws/.context/reports/t.html") != \
       g.spec_name("y_ws/.context/reports/t.html")
print("  ok: the prefix separates a shared basename")
# And a sample the rule cannot address stops the gate instead of passing it.
try:
    g.check_names([{"path": "x_ws/a/t.html"}, {"path": "x_ws/b/t.html"}])
except SystemExit as e:
    assert "same spec name" in str(e), e
    print("  ok: two pages that map to one spec name stop the gate")
else:
    raise AssertionError("check_names let two pages share one spec name")
if sys.argv[2]:
    sample = json.load(open(os.path.join(sys.argv[2], "corpus-sample.json")))
    names = [g.spec_name(p["path"]) for p in sample["pages"]]
    assert len(set(names)) == len(names), "two pages share a spec name"
    g.check_names(sample["pages"])
    print("  ok: %d distinct spec names over the frozen sample" % len(names))
else:
    print("SKIP the naming rule over the frozen sample: "
          "AIDEX_SPEC_CORPUS not set")
PY
[ $? -eq 0 ] || bad "the naming rule"

echo
echo "== every escape detector fires on its own shape =="
python3 - "$HERE" "$tmp" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import goal_gate as g
tmp = sys.argv[2]
fails = []


def spec(name, text):
    path = os.path.join(tmp, name + ".spec.md")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path


def case(label, path, expect, needle=""):
    why = g.escapes_in(path)
    hit = bool(why)
    if hit != expect or (needle and not any(needle in w for w in why)):
        fails.append("%s: %r" % (label, why))
        print("FAIL: " + label + " -> " + repr(why))
    else:
        print("  ok: " + label)


clean = spec("clean", '::: masthead {eyebrow="e"}\n# T\n\nUn párrafo.\n:::\n')
case("a plain spec needs no escape", clean, False)

# Detector 1: an escape-hatch fence. No such type is registered, so this is the
# guard against one arriving quietly rather than a shape in the corpus.
for t in g.ESCAPE_TYPES:
    p = spec("hatch-" + t, "::: %s\n<b>x</b>\n:::\n" % t)
    case("a `%s` fence counts as an escape" % t, p, True, "escape-hatch")

# Detector 2: passthrough. It cannot fire through the grammar today — `esc()`
# runs on every author string — so it is proved against a body that DOES carry
# the author's tag, which is exactly what a future passthrough would produce.
p = spec("passthru", "Un `<style>` citado en prosa.\n")
case("a tag quoted in prose is NOT a passthrough", p, False)
bare = spec("bare", "Un <style> citado en prosa.\n")
case("a tag ESCAPED into the page is not one either", bare, False)
real = g.corpus_diff.build_body
try:
    g.corpus_diff.build_body = \
        lambda path, **kw: "<main>Un <style> citado en prosa.</main>"
    case("a tag that reaches the page AS MARKUP is a passthrough", bare, True,
         "passes")
finally:
    g.corpus_diff.build_body = real

# Detector 3a: built output kept beside a spec is a hand-edit.
p = spec("handedit", "Un párrafo.\n")
open(os.path.join(tmp, "handedit.html"), "w").write("<main></main>")
case("built HTML beside a spec is a hand-edit", p, True, "hand-edit")

# Detector 3b: the sidecar a converter writes when the grammar cannot say it.
p = spec("sidecar", "Un párrafo.\n")
open(os.path.join(tmp, "sidecar.escape.md"), "w").write("a nested gallery row\n")
case("an `.escape.md` sidecar is counted, not tolerated", p, True,
     "nested gallery row")

# A figure block's file is INPUT the grammar names, not a file beside the spec
# that nothing reads: it is no escape. An .html beside the spec still is.
os.makedirs(os.path.join(tmp, "figures"), exist_ok=True)
open(os.path.join(tmp, "figures", "withfig--fig1.svg"), "w").write(
    '<svg viewBox="0 0 4 4"><rect class="acc" width="4" height="4"/></svg>')
p = spec("withfig", '::: figure {src="figures/withfig--fig1.svg" title="t"}\n:::\n')
case("a spec embedding a figure file needs no escape", p, False)
open(os.path.join(tmp, "withfig.html"), "w").write("<main></main>")
case("…and built HTML beside that spec is still a hand-edit", p, True, "hand-edit")

# A code fence hides its contents from every line-level detector.
p = spec("fenced", "```\n::: html\n<b>x</b>\n```\n")
case("an escape-hatch fence inside a CODE fence is documentation", p, False)

sys.exit(1 if fails else 0)
PY
[ $? -eq 0 ] || bad "an escape detector"

echo
echo "== the floor is what makes a regression visible =="
floor_check() {
  AIDEX_SPEC_CORPUS="$2" python3 - "$HERE" "$1" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1])
import goal_gate as g
floor = json.load(open(g.FLOOR))
assert set(floor) == {"corpus", "escapes"}, floor
assert floor["escapes"] == 0, "the escapes floor is 0 — that is the plan's claim"
specs = [f for f in os.listdir(g.SPECS) if f.endswith(".spec.md")]
assert floor["corpus"] == len(specs), (
    "GATE-FLOOR corpus=%d but %d spec(s) are committed — the floor is advanced "
    "by hand, and a converter that adds a spec advances it in the same change"
    % (floor["corpus"], len(specs)))
print("  ok: [%s] the floor matches the committed specs, and escapes' floor "
      "is 0" % sys.argv[2])
PY
  [ $? -eq 0 ] || bad "the gate floor [$1]"
}
floor_check synthetic "$MINI"
if [ -n "$REAL" ]; then floor_check corpus "$REAL"; else skip "the floor of the real corpus"; fi

echo
echo "== the blind trial: only a well-formed log can read 3/3 =="
AIDEX_SPEC_CORPUS="$MINI" python3 - "$HERE" "$tmp" "$REAL" <<'BLINDPY'
import io, os, sys
from contextlib import redirect_stdout, redirect_stderr
sys.path.insert(0, sys.argv[1])
import goal_gate as g
tmp = os.path.join(sys.argv[2], "blind")
os.makedirs(tmp, exist_ok=True)
REAL = sys.argv[3]
fails = []
n = [0]


def case(label, text, want, path=None):
    """`text is None` means: the file does not exist at all."""
    if path is None:
        n[0] += 1
        path = os.path.join(tmp, "case%02d.md" % n[0])
        if text is None:
            path = os.path.join(tmp, "absent.md")
        else:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
    got, note = g.blind_count(path)
    if got != want:
        fails.append(label)
        print("FAIL: %s -> got %d, want %d (%s)" % (label, got, want, note))
    else:
        print("  ok: %s -> %d%s" % (label, got, (" — %s" % note) if note else ""))


def rec(run="r9", build1="OK", build2="OK", html="no", verdict="pass"):
    return ("run=%s spec=s.spec.md verb=decide build1=%s build2=%s "
            "handwritten-html=%s verdict=%s" % (run, build1, build2, html, verdict))


def log(records, runs=3, version=1, close=True):
    out = ["# a log", "",
           "<!-- BLIND-TRIAL-VERDICTS v%d runs=%d -->" % (version, runs),
           "```verdicts"] + list(records)
    if close:
        out.append("```")
    return "\n".join(out) + "\n"


three = [rec("r1"), rec("r2"), rec("r3")]

if REAL:
    case("the COMMITTED log counts 3", None, 3,
         path=os.path.join(REAL, "blind-trial-log.md"))
else:
    print("SKIP the COMMITTED log counts 3: AIDEX_SPEC_CORPUS not set")
case("the synthetic corpus's log counts 3", None, 3, path=g.BLIND_LOG)
case("a synthetic well-formed log counts 3", log(three), 3)

# Every shape a broken log arrives in. None of them may read 3.
case("a missing log counts 0", None, 0)
case("an empty log counts 0", "", 0)
case("a truncated log (fence never closed) counts 0", log(three, close=False), 0)
case("a truncated log (a record lost) counts 0", log(three[:2]), 0)
case("a padded log (a fourth record) counts 0", log(three + [rec("r4")]), 0)
case("a duplicated run id counts 0", log([rec("r1"), rec("r2"), rec("r2")]), 0)
case("a log with no header counts 0",
     "```verdicts\n" + "\n".join(three) + "\n```\n", 0)
case("two headers count 0", log(three) + log(three), 0)
case("a header from a future version counts 0", log(three, version=2), 0)
case("a log that lowers its own denominator counts 0", log(three[:2], runs=2), 0)
case("a fence that drifted away from its header counts 0",
     log(three).replace("```verdicts", "Some prose.\n\n```verdicts"), 0)

# Reworded records: the fields ARE the record, in one fixed order.
case("a record missing a field counts 0",
     log([rec("r1").replace(" handwritten-html=no", ""), rec("r2"), rec("r3")]), 0)
case("a record with its fields reordered counts 0",
     log(["spec=s.spec.md run=r1 verb=decide build1=OK build2=OK "
          "handwritten-html=no verdict=pass", rec("r2"), rec("r3")]), 0)
case("trailing junk on a record counts 0",
     log([rec("r1") + " and it was fine", rec("r2"), rec("r3")]), 0)

# The EVIDENCE, not the verdict word, is what a run is counted on.
case("an honest failing run counts 2, not 3",
     log([rec("r1"), rec("r2"), rec("r3", build2="FAIL", verdict="fail")]), 2)
case("a verdict that contradicts its evidence counts 0",
     log([rec("r1"), rec("r2"), rec("r3", build2="FAIL")]), 0)
case("hand-written HTML under a passing verdict counts 0",
     log([rec("r1"), rec("r2"), rec("r3", html="yes")]), 0)
case("an honest hand-written-HTML run counts 2",
     log([rec("r1"), rec("r2"), rec("r3", html="yes", verdict="fail")]), 2)
case("an unknown build token is not OK",
     log([rec("r1"), rec("r2"), rec("r3", build1="ok", verdict="fail")]), 2)

# End to end: the LINE the gate prints, with a malformed log in place.
broken = os.path.join(tmp, "broken-e2e.md")
with open(broken, "w", encoding="utf-8") as fh:
    fh.write(log(three, close=False))
real, buf, err = g.BLIND_LOG, io.StringIO(), io.StringIO()
try:
    g.BLIND_LOG = broken
    with redirect_stdout(buf), redirect_stderr(err):
        rc = g.main([])
finally:
    g.BLIND_LOG = real
line = [l for l in buf.getvalue().split("\n") if l.startswith("blind:")]
if line != ["blind: 0/3"]:
    fails.append("the gate's own line under a malformed log")
    print("FAIL: the gate printed %r on a malformed log" % line)
else:
    print("  ok: the gate prints 'blind: 0/3' on a malformed log, never 3/3")
if "blind trial not counted" not in err.getvalue():
    fails.append("the reason on stderr")
    print("FAIL: no reason on stderr: %r" % err.getvalue())
else:
    print("  ok: and says on stderr why it could not count it")
if rc != 0:
    fails.append("a malformed blind log must not change the exit status")
    print("FAIL: exit %d — blind is informative; corpus and escapes gate" % rc)
else:
    print("  ok: blind stays informative — it does not set the exit status")

sys.exit(1 if fails else 0)
BLINDPY
[ $? -eq 0 ] || bad "the blind-trial count"

echo
echo "== the figure census: only a census that covers the sample can count =="
AIDEX_SPEC_CORPUS="$MINI" python3 - "$HERE" "$tmp" "$REAL" <<'CENSUSPY'
import io, json, os, sys
from contextlib import redirect_stdout, redirect_stderr
sys.path.insert(0, sys.argv[1])
import goal_gate as g
tmp = os.path.join(sys.argv[2], "census")
os.makedirs(tmp, exist_ok=True)
REAL = sys.argv[3]
sample = json.load(open(g.SAMPLE))
PAGES, ROOT = sample["pages"], sample["root"]
fails = []
n = [0]

# Read back from the synthetic corpus's census, so every case below is a
# mutation of a census that parses rather than a second hand-kept copy of it.
assert g.census_records(), "the synthetic census parses"
GOOD = [ln.strip() for ln in
        open(g.FIGURE_CENSUS, encoding="utf-8").read()
        .split("```census")[1].split("```")[0].strip().split("\n")]
N = len(GOOD)
alpha = "alpha/reports/2026-01-01-one-flow.html"
beta = "beta/reports/2026-01-02-two-figures.html"
gamma = "gamma/reports/2026-01-03-chart-only.html"
A1 = "page=%s fig=1 kind=flow rung=1 block=diagram as=row" % alpha
B1 = "page=%s fig=1 kind=chart rung=1 block=chart as=bar" % beta
B2 = "page=%s fig=2 kind=flow rung=1 block=diagram as=before-after" % beta
G1 = "page=%s fig=1 kind=chart rung=1 block=chart as=line" % gamma
assert GOOD == [A1, B1, B2, G1], GOOD


def census(records, figures=None, close=True, version=2, extensions=""):
    n[0] += 1
    figures = len(records) if figures is None else figures
    out = ["# a census", "",
           "<!-- FIGURE-CENSUS v%d figures=%d extensions=%s -->"
           % (version, figures, extensions),
           "```census"] + list(records)
    if close:
        out.append("```")
    path = os.path.join(tmp, "case%02d.md" % n[0])
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    return path


def raw(text):
    n[0] += 1
    path = os.path.join(tmp, "raw%02d.md" % n[0])
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path


def swap(records, old, new):
    return [new if r == old else r for r in records]


def case(label, path, want_carried, want_total, root=None):
    got, total, _ladder, notes, _short = g.figure_count(PAGES, root or ROOT, path)
    if (got, total) != (want_carried, want_total):
        fails.append(label)
        print("FAIL: %s -> got %r/%r, want %r/%r (%s)"
              % (label, got, total, want_carried, want_total, "; ".join(notes)))
    else:
        print("  ok: %s -> %s/%s%s"
              % (label, got, total, (" — %s" % notes[0]) if notes else ""))


if REAL:
    real_sample = json.load(open(os.path.join(REAL, "corpus-sample.json")))
    mini_specs, g.SPECS = g.SPECS, os.path.join(REAL, "corpus-specs")
    try:
        got, total, ladder, notes, _short = g.figure_count(
            real_sample["pages"], real_sample["root"],
            os.path.join(REAL, "figure-census.md"))
    finally:
        g.SPECS = mini_specs
    if total != 45 or ladder is None or sum(ladder.values()) != 45:
        fails.append("the COMMITTED census")
        print("FAIL: the COMMITTED census covers the sample's 45 figures -> "
              "got %r/%r, ladder %r (%s)" % (got, total, ladder, "; ".join(notes)))
    else:
        print("  ok: the COMMITTED census covers the sample's 45 figures -> "
              "%d/%d carried, ladder %r" % (got, total, ladder))
    # Review finding 3: a rung-2 figure's GRAPH-LABELS line must account for
    # every box of the ORIGINAL. Each <text> that sits inside a <rect> of the
    # original figure is either inside one of the census's labels for it or
    # quoted, verbatim, in that figure's "What the carrying form loses" cell.
    import html as _h, re as _r
    ctext = open(os.path.join(REAL, "figure-census.md"), encoding="utf-8").read()
    rows = {}
    for ln in ctext.split("\n"):
        m = _r.match(r"^\| `(\S+)` (\S+) \| (\d+) \| 2 · dot \|.*\|([^|]*)\|$", ln)
        if m:
            rows[(m.group(1), m.group(2), int(m.group(3)))] = m.group(4)
    def _num(v):
        try:
            return float(v)
        except (TypeError, ValueError):
            return None
    def _attr(tag, name):
        m = _r.search(r'\s%s="([^"]*)"' % name, tag)
        return m.group(1) if m else None
    unaccounted, n_rung2 = [], 0
    for rec in g.census_records(os.path.join(REAL, "figure-census.md")):
        if rec["rung"] != "2":
            continue
        n_rung2 += 1
        page = open(os.path.join(real_sample["root"], rec["page"]),
                    encoding="utf-8").read()
        fig = g.FIGURE_ELEMENT.findall(page)[rec["fig"] - 1]
        project, base = rec["page"].split("/")[0], os.path.basename(rec["page"])
        loses = next((v for (p, stem, f), v in rows.items() if p == project
                      and base.startswith(stem) and f == rec["fig"]), None)
        if loses is None:
            unaccounted.append("%s fig %d: no census row" % (base, rec["fig"]))
            continue
        boxes = []
        for t in _r.findall(r"<rect\b[^>]*>", fig):
            x, y = _num(_attr(t, "x")), _num(_attr(t, "y"))
            w, hh = _num(_attr(t, "width")), _num(_attr(t, "height"))
            if None not in (x, y, w, hh):
                boxes.append((x, y, x + w, y + hh))
        for m in _r.finditer(r"<text\b([^>]*)>(.*?)</text>", fig, _r.S):
            x, y = _num(_attr(m.group(1), "x")), _num(_attr(m.group(1), "y"))
            words = " ".join(_h.unescape(_r.sub(r"<[^>]+>", "", m.group(2))).split())
            if x is None or y is None or not words:
                continue
            if not any(x0 <= x <= x1 and y0 <= y <= y1 for x0, y0, x1, y1 in boxes):
                continue
            if any(words in lab for lab in rec["labels"]) or words in loses:
                continue
            unaccounted.append("%s fig %d: %r" % (base, rec["fig"], words))
    if unaccounted:
        fails.append("rung-2 boxes accounted for")
        print("FAIL: every boxed text of a rung-2 original is a census label or "
              "quoted as a loss — %d are neither: %s"
              % (len(unaccounted), "; ".join(unaccounted)))
    else:
        print("  ok: every boxed text of the %d rung-2 originals is a census "
              "label or quoted in its figure's loses cell" % n_rung2)
else:
    print("SKIP the COMMITTED census covers the sample's 45 figures: "
          "AIDEX_SPEC_CORPUS not set")
case("the synthetic census is fully carried", None, N, N)
case("a synthetic copy of it counts the same", census(GOOD), N, N)

# Every shape a broken census arrives in. None may read as carried, and none
# may print a denominator: `0/0` would read as done.
case("a missing census has no denominator",
     os.path.join(tmp, "absent.md"), 0, None)
case("an empty file has no denominator", raw(""), 0, None)
case("a census that declares figures=0 is refused", census([], figures=0), 0, None)
case("a truncated census (fence never closed)", census(GOOD, close=False), 0, None)
case("a truncated census (a record lost)", census(GOOD[:-1], figures=N), 0, None)
case("a padded census (one record too many)", census(GOOD, figures=N + 1), 0, None)
case("a census from a future version", census(GOOD, version=3), 0, None)
case("a v1 census, from before rung-3 records carried a sha256",
     census(GOOD, version=1), 0, None)
case("a census with no header",
     raw("```census\n" + "\n".join(GOOD) + "\n```\n"), 0, None)
case("two headers",
     raw(open(census(GOOD), encoding="utf-8").read()
         + open(census(GOOD), encoding="utf-8").read()), 0, None)
case("a fence that drifted away from its header",
     raw(open(census(GOOD), encoding="utf-8").read()
         .replace("```census", "Some prose.\n\n```census")), 0, None)
case("a record with its fields reordered",
     census(swap(GOOD, A1, A1.replace("fig=1 kind=flow", "kind=flow fig=1"))), 0, None)
case("a record with trailing junk", census(swap(GOOD, A1, A1 + " why=because")),
     0, None)
case("an unknown kind", census(swap(GOOD, A1, A1.replace("kind=flow", "kind=doodle"))),
     0, None)
case("a rung off the ladder", census(swap(GOOD, A1, A1.replace("rung=1", "rung=4"))),
     0, None)
case("a table rung, which the gate does not count",
     census(swap(GOOD, A1, A1.replace("rung=1", "rung=table"))), 0, None)
case("a block that does not carry its rung (a chart on rung 2)",
     census(swap(GOOD, B1, B1.replace("rung=1", "rung=2"))), 0, None)
case("a diagram shape neither built nor listed as an extension",
     census(swap(GOOD, A1, A1.replace("as=row", "as=swimlane"))), 0, None)
case("a graph that is not DOT",
     census(swap(GOOD, A1, A1.replace("rung=1 block=diagram as=row",
                                      "rung=2 block=graph as=svg"))), 0, None)
case("a figure file type the block cannot embed",
     census(swap(GOOD, A1, A1.replace("rung=1 block=diagram as=row",
                                      "rung=3 block=figure as=gif")
                         + " sha256=" + "0" * 64)), 0, None)
case("fig=0 is refused", census(swap(GOOD, A1, A1.replace("fig=1", "fig=0"))), 0, None)

# The rung-1 extension list is checked, not just written.
LANES = [swap(GOOD, A1, A1.replace("as=row", "as=lanes"))]
LANES = swap(LANES[0], B2, B2.replace("as=before-after", "as=lanes"))
case("an extension asked for by two records parses — and, unbuilt, never "
     "matches", census(LANES, extensions="diagram:lanes"), 1, N)
case("an extension asked for by one record is refused",
     census(swap(GOOD, A1, A1.replace("as=row", "as=lanes")),
            extensions="diagram:lanes"), 0, None)
case("an extension that is already built is refused",
     census(GOOD, extensions="chart:bar"), 0, None)
case("an extension on a block that is not rung 1 is refused",
     census(GOOD, extensions="graph:neato"), 0, None)

# The four the census exists to catch. Each PARSES and still cannot count,
# because the files say otherwise.
case("one figure recorded twice", census(GOOD + [A1], figures=N + 1), 0, None)
case("a fig that the page does not draw",
     census(swap(GOOD, A1, A1.replace("fig=1", "fig=9"))), 0, None)
case("a census that misses one of the page's figures (fewer than it draws)",
     census([r for r in GOOD if r != B2]), 0, None)
case("a census that records more figures than the page draws",
     census(GOOD + [G1.replace("fig=1", "fig=2")]), 0, None)
case("a page outside the frozen sample",
     census(GOOD + ["page=zz_ws/.context/reports/x.html fig=1 kind=flow "
                    "rung=1 block=diagram as=row"]), 0, None)
case("a spec carrying a figure on a different rung than assigned",
     census(swap(GOOD, A1, A1.replace("rung=1 block=diagram as=row",
                                      "rung=3 block=figure as=svg")
                         + " sha256=" + "0" * 64)), N - 1, N)

# …and on a page with a second, carried figure, so the mismatch visibly costs
# the page's OTHER figure too rather than only the one it is about.
case("a spec carrying a figure on a different rung, beside a carried one",
     census(swap(GOOD, B2, B2.replace("rung=1 block=diagram as=before-after",
                                      "rung=3 block=figure as=svg")
                         + " sha256=" + "0" * 64)), N - 2, N)
case("a spec carrying the figure in another form of the same rung",
     census(swap(GOOD, G1, G1.replace("as=line", "as=bar"))), N - 1, N)
# Position: `beta`'s spec draws the chart, then the diagram. A census that
# records them the other way round has the spec's second block with no record
# left after the first, so the page carries nothing.
case("a census whose order disagrees with the spec's",
     census([A1, B1.replace("fig=1", "fig=2"), B2.replace("fig=2", "fig=1"), G1]),
     N - 2, N)

# A spec is judged as it BUILDS, not as it parses (Phase 1 review, F1). The
# alpha page's figure is re-assigned to rung 3 and its spec rewritten to embed a
# file, in a scratch copy of the specs: once with a file the block embeds, once
# with one it refuses (a <script>), once with no file at all. Parsing alone
# credits all three.
import shutil as _sh
ALPHA_SPEC = "alpha__2026-01-01-one-flow.spec.md"
SVG_OK = ('<svg viewBox="0 0 10 10"><rect class="acc" width="10" height="10"/>'
          '</svg>')
SVG_BAD = ('<svg viewBox="0 0 10 10"><script>alert(1)</script>'
           '<rect class="acc" width="10" height="10"/></svg>')


def alpha_as_figure(label, src, content):
    """`g.SPECS` pointed at a copy whose alpha spec embeds `src`."""
    d = os.path.join(tmp, "specs-" + label)
    _sh.copytree(g.SPECS, d)
    if content is not None:
        os.makedirs(os.path.join(d, os.path.dirname(src)), exist_ok=True)
        with open(os.path.join(d, src), "w", encoding="utf-8") as fh:
            fh.write(content)
    with open(os.path.join(d, ALPHA_SPEC), "w", encoding="utf-8") as fh:
        fh.write('::: masthead {eyebrow="e"}\n# T\n\nUn párrafo.\n:::\n\n'
                 '::: figure {src="%s" title="t"}\n:::\n' % src)
    return d


def sha(content):
    import hashlib
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def rung3(line, content=SVG_OK):
    """The record re-assigned to rung 3, with the sha256 of `content` — the
    census's record of which file IS the original (Phase 1 review, F2)."""
    return line.replace("rung=1 block=diagram as=row",
                        "rung=3 block=figure as=svg") + " sha256=" + sha(content)


def pages_with_alpha(original):
    """A copy of the sample's pages whose alpha page draws `original` as its
    figure 1 — the ORIGINAL the gate re-extracts and re-hashes (review F-E)."""
    root = os.path.join(tmp, "pages-%s" % sha(original)[:12])
    if not os.path.isdir(root):
        _sh.copytree(ROOT, root)
        page = os.path.join(root, alpha)
        text = open(page, encoding="utf-8").read()
        m = g.FIGURE_ELEMENT.search(text)
        with open(page, "w", encoding="utf-8") as fh:
            fh.write(text[:m.start()] + "<figure>" + original + "</figure>"
                     + text[m.end():])
    return root


def with_specs(label, d, path, want_carried, want_total, original=SVG_OK):
    keep, g.SPECS = g.SPECS, d
    try:
        case(label, path, want_carried, want_total,
             root=pages_with_alpha(original))
    finally:
        g.SPECS = keep


with_specs("a figure block that builds is carried",
           alpha_as_figure("f1-ok", "figures/a.svg", SVG_OK),
           census(swap(GOOD, A1, rung3(A1))), N, N)
with_specs("a figure block the build refuses (a <script>) is NOT carried",
           alpha_as_figure("f1-bad", "figures/a.svg", SVG_BAD),
           census(swap(GOOD, A1, rung3(A1, SVG_BAD))), N - 1, N, original=SVG_BAD)
with_specs("a figure block whose file does not exist is NOT carried",
           alpha_as_figure("f1-none", "figures/nope.svg", None),
           census(swap(GOOD, A1, rung3(A1))), N - 1, N)
# A waiver (the owner's amendment of 2026-09-24: 8 literal-colour originals are
# not carried, by name) excuses ONE uncarried record from completion and
# nothing else. `short` is what still stands between the count and done. A
# waiver is checked, not trusted: its record must be rung 3 svg with a known
# reason, its sha256 must still be the original's, and the original must still
# be refused by the figure rules — otherwise the waiver is stale and blocks.
SVG_HEX = ('<svg viewBox="0 0 10 10"><rect fill="#1E5F4B" width="10" '
           'height="10"/></svg>')
WAIVED = rung3(A1, SVG_HEX) + " waived=literal-colours"


def short(label, path, want, original=SVG_OK):
    got, total, _l, notes, sh = g.figure_count(
        PAGES, pages_with_alpha(original), path)
    if sh != want:
        fails.append(label)
        print("FAIL: %s -> short %r, want %r (%s)" % (label, sh, want, "; ".join(notes)))
    else:
        print("  ok: %s -> %s/%s, short %s" % (label, got, total, sh))


short("the synthetic census, fully carried, is short of nothing", census(GOOD), 0)
short("an uncarried record with no waiver keeps the gate short",
      census(swap(GOOD, A1, rung3(A1, SVG_HEX))), 1, SVG_HEX)
short("a waived record whose original is still refused is excused",
      census(swap(GOOD, A1, WAIVED)), 0, SVG_HEX)
got, total, _l, _n, _s = g.figure_count(
    PAGES, pages_with_alpha(SVG_HEX), census(swap(GOOD, A1, WAIVED)))
if (got, total) != (N - 1, N):
    fails.append("waiver moves no count")
    print("FAIL: a waiver moved the count -> %r/%r" % (got, total))
else:
    print("  ok: ...and a waiver moves no count: %d/%d" % (got, total))
short("a waived record whose census sha256 is not the original's blocks "
      "(the original changed under the waiver)",
      census(swap(GOOD, A1, WAIVED)), 1, SVG_HEX.replace("1E5F4B", "1E5F4C"))
short("a waived record whose original now passes the figure rules blocks "
      "(the reason is gone)",
      census(swap(GOOD, A1, rung3(A1, SVG_OK) + " waived=literal-colours")), 1)
case("a waiver on a rung-1 record is refused",
     census(swap(GOOD, A1, A1 + " waived=literal-colours")), 0, None)
case("a waiver with a reason outside the closed list is refused",
     census(swap(GOOD, A1, rung3(A1, SVG_HEX) + " waived=too-hard")), 0, None)
case("a waiver with no reason is malformed",
     census(swap(GOOD, A1, rung3(A1, SVG_HEX) + " waived=")), 0, None)
case("a waiver before the sha256 is malformed (the order is fixed)",
     census(swap(GOOD, A1, rung3(A1, SVG_HEX).replace(
         " sha256=", " waived=literal-colours sha256="))), 0, None)
short("a census that cannot be read is short, never done",
      census(GOOD, version=3), 1)

# The gate's own path: `main` hands `figure_count` the set of specs
# `measure()` built, so nothing is built twice. A spec outside that set is one
# that did not build, whatever its blocks parse to.
got, total, _l, _n, _s = g.figure_count(PAGES, ROOT, None, built=set())
if (got, total) != (0, N):
    fails.append("built=set()")
    print("FAIL: no spec in measure()'s built set -> got %r/%r, want 0/%d"
          % (got, total, N))
else:
    print("  ok: no spec in measure()'s built set carries nothing -> 0/%d" % N)

# A rung-3 figure counts only when the embedded file IS the original (Phase 1
# review, F2): the census records its sha256 and the gate re-hashes the file
# the spec's block names. A placeholder with the right extension builds, and
# must never count.
PLACEHOLDER = SVG_OK.replace('width="10"', 'width="9"')
with_specs("a placeholder SVG that builds, but is not the original, is NOT "
           "carried", alpha_as_figure("f2-placeholder", "figures/a.svg", PLACEHOLDER),
           census(swap(GOOD, A1, rung3(A1))), N - 1, N)
# …and the census's sha256 is itself re-derived (review F-E): the gate extracts
# the figure from the ORIGINAL page and hashes it, and all three — census,
# embedded file, original — must agree. A census that records the placeholder's
# hash beside the placeholder has not recorded the original.
with_specs("a record whose sha256 matches the embedded file but not the "
           "original page's figure is NOT carried",
           alpha_as_figure("fe-census-lies", "figures/a.svg", PLACEHOLDER),
           census(swap(GOOD, A1, rung3(A1, PLACEHOLDER))), N - 1, N)
case("a rung-3 record without its sha256 is refused",
     census(swap(GOOD, A1, rung3(A1).split(" sha256=")[0])), 0, None)
case("a sha256 on a record that is not rung 3 is refused",
     census(swap(GOOD, A1, A1 + " sha256=" + sha(SVG_OK))), 0, None)
case("a sha256 that is not 64 hex digits is refused",
     census(swap(GOOD, A1, rung3(A1) + "0")), 0, None)

# Position, on the matcher itself: uncarried records are skipped, a block is
# never.
R = [{"fig": 1, "block": "chart", "as": "bar"},
     {"fig": 2, "block": "diagram", "as": "pipeline"},
     {"fig": 3, "block": "figure", "as": "svg"}]
for label, blocks, want in [
        ("no block carries nothing", [], 0),
        ("a later figure carried while an earlier one is not",
         [("diagram", "row")], 1),
        ("every figure in order", [("chart", "bar"), ("diagram", "row"),
                                   ("figure", "svg")], 3),
        ("two blocks out of order", [("diagram", "row"), ("chart", "bar")], None),
        ("one block for a figure recorded once, drawn twice",
         [("chart", "bar"), ("chart", "bar")], None),
        # Forms are disjoint across blocks today; the block is compared anyway,
        # so a future form name shared by two blocks cannot cross rungs.
        ("the right form on the wrong block", [("chart", "svg")], None)]:
    got = g.carried_on_page(R, blocks)
    if got != want:
        fails.append(label)
        print("FAIL: carried_on_page: %s -> %r, want %r" % (label, got, want))
    else:
        print("  ok: carried_on_page: %s -> %r" % (label, got))

# Rung 2's content (Phase 5, review finding F2): a rung-2 record counts only
# against a GRAPH-LABELS line, and only when the graph's node labels are the
# census's. Parser cases first — none needs Graphviz.
A1G = A1.replace("rung=1 block=diagram as=row", "rung=2 block=graph as=dot")


def with_labels(records, lines, header="<!-- GRAPH-LABELS v1 -->", close=True):
    text = open(census(records), encoding="utf-8").read()
    text += "\n%s\n```graph-labels\n%s\n%s" % (header, "\n".join(lines),
                                               "```\n" if close else "")
    return raw(text)


LA = ("page=%s fig=1 edges=solid:2,dashed:0 labels=Primero | Segundo | Tercero"
      % alpha)
case("a rung-2 record with no GRAPH-LABELS block is refused",
     census(swap(GOOD, A1, A1G)), 0, None)
case("a rung-2 record with its labels line parses (alpha's spec draws a row, "
     "so alpha carries nothing)", with_labels(swap(GOOD, A1, A1G), [LA]), N - 1, N)
case("a rung-2 record whose labels line is missing is refused",
     with_labels(swap(GOOD, A1, A1G), []), 0, None)
case("a labels line for a rung-1 record is refused",
     with_labels(swap(GOOD, A1, A1G),
                 [LA, "page=%s fig=1 edges=solid:0,dashed:0 labels=x" % gamma]),
     0, None)
case("a labels line recorded twice is refused",
     with_labels(swap(GOOD, A1, A1G), [LA, LA]), 0, None)
case("a labels line with no edges= field is refused",
     with_labels(swap(GOOD, A1, A1G), [LA.replace(" edges=solid:2,dashed:0", "")]),
     0, None)
case("an edges= field naming an unknown kind is refused",
     with_labels(swap(GOOD, A1, A1G), [LA.replace("dashed:0", "dotted:0")]),
     0, None)
case("an empty label is refused",
     with_labels(swap(GOOD, A1, A1G), [LA + " | "]), 0, None)
case("a labels fence never closed is refused",
     with_labels(swap(GOOD, A1, A1G), [LA], close=False), 0, None)
case("a labels block from a future version is refused",
     with_labels(swap(GOOD, A1, A1G), [LA],
                 header="<!-- GRAPH-LABELS v2 -->"), 0, None)

# On the matcher: a record naming labels is carried only by a graph block
# drawing the same multiset of labels; a graph that did not build carries none.
E1 = {"solid": 1, "dashed": 1}
RL = [{"fig": 1, "block": "graph", "as": "dot", "labels": ["a", "b"],
       "edges": E1}]
for label, blocks, want in [
        ("a graph with the census's labels and edges",
         [("graph", "dot", None, ["a", "b"], E1)], 1),
        ("a graph with one label renamed",
         [("graph", "dot", None, ["a", "c"], E1)], None),
        ("a graph with an extra node",
         [("graph", "dot", None, ["a", "b", "c"], E1)], None),
        ("a graph with the labels and every edge deleted",
         [("graph", "dot", None, ["a", "b"], {"solid": 0, "dashed": 0})], None),
        ("a graph with an edge's kind swapped",
         [("graph", "dot", None, ["a", "b"], {"solid": 2, "dashed": 0})], None),
        ("a graph that did not build", [("graph", "dot", None, None, None)], None),
        ("a graph block with no content at all", [("graph", "dot")], None)]:
    got = g.carried_on_page(RL, blocks)
    if got != want:
        fails.append(label)
        print("FAIL: carried_on_page: %s -> %r, want %r" % (label, got, want))
    else:
        print("  ok: carried_on_page: %s -> %r" % (label, got))

# End to end over a real spec, which needs Graphviz to build its graph.
import graph_svg
if not graph_svg.dot_path():
    print("SKIP the graph-label end-to-end cases: no `dot` on PATH")
else:
    gdir = os.path.join(tmp, "graphcase")
    os.makedirs(os.path.join(gdir, "specs"))
    os.makedirs(os.path.join(gdir, "pages", "delta", "reports"))
    delta = "delta/reports/2026-01-04-graph.html"
    with open(os.path.join(gdir, "pages", delta), "w") as fh:
        fh.write("<main><figure><svg></svg></figure></main>")
    with open(os.path.join(gdir, "specs", g.spec_name(delta)), "w") as fh:
        fh.write('::: graph {title="t"}\ndigraph {\n  a [label="Primero"];\n'
                 '  b [label="Segundo"];\n  a -> b [label="arista"];\n}\n:::\n')
    DREC = "page=%s fig=1 kind=flow rung=2 block=graph as=dot" % delta
    DPAGES = [{"path": delta}]
    specs_before = g.SPECS
    g.SPECS = os.path.join(gdir, "specs")
    try:
        for label, edges, labels, want in [
                ("a graph drawing the census's labels and edges is carried",
                 "solid:1,dashed:0", "Segundo | Primero", 1),
                ("a graph missing one of the census's labels is not",
                 "solid:1,dashed:0", "Primero | Segundo | Tercero", 0),
                ("an edge label is not a node label",
                 "solid:1,dashed:0", "Primero | Segundo | arista", 0),
                ("the census's labels with no edge drawn is not carried",
                 "solid:0,dashed:0", "Primero | Segundo", 0),
                ("a solid edge where the census has a dashed one is not",
                 "solid:0,dashed:1", "Primero | Segundo", 0)]:
            got, total, _l, notes, _s = g.figure_count(
                DPAGES, os.path.join(gdir, "pages"),
                with_labels([DREC], ["page=%s fig=1 edges=%s labels=%s"
                                     % (delta, edges, labels)]))
            if (got, total) != (want, 1):
                fails.append(label)
                print("FAIL: %s -> %r/%r (%s)" % (label, got, total, "; ".join(notes)))
            else:
                print("  ok: %s -> %d/1" % (label, got))
        real_dot = graph_svg.dot_path
        graph_svg.dot_path = lambda: None
        try:
            got, total, _l, _n, _s = g.figure_count(
                DPAGES, os.path.join(gdir, "pages"),
                with_labels([DREC], ["page=%s fig=1 edges=solid:1,dashed:0 "
                                     "labels=Primero | Segundo" % delta]))
        finally:
            graph_svg.dot_path = real_dot
        if (got, total) != (0, 1):
            fails.append("no dot carries nothing")
            print("FAIL: with no dot the graph still counted: %r/%r" % (got, total))
        else:
            print("  ok: with no dot on PATH the same graph carries nothing -> 0/1")
    finally:
        g.SPECS = specs_before

# End to end: the LINES the gate prints, with a malformed census in place. The
# contract IS measured here, so the census is the only thing that can fail.
broken = census(GOOD, close=False)
real, buf, err = g.FIGURE_CENSUS, io.StringIO(), io.StringIO()
try:
    g.FIGURE_CENSUS = broken
    with redirect_stdout(buf), redirect_stderr(err):
        rc = g.main([])
finally:
    g.FIGURE_CENSUS = real
lines = buf.getvalue().split("\n")
got = [l for l in lines if l.startswith(("figures:", "ladder:"))]
if got != ["figures: 0/unknown", "ladder: unknown"]:
    fails.append("the gate's own lines under a malformed census")
    print("FAIL: the gate printed %r on a malformed census" % got)
else:
    print("  ok: the gate prints 'figures: 0/unknown' and 'ladder: unknown' "
          "on a malformed census")
import re as _re
GATE = _re.compile(r'^figures: ([0-9]+)/\1$')
if got and GATE.match(got[0]):
    fails.append("a malformed census must not satisfy the N/N gate")
    print("FAIL: %r satisfies ^figures: ([0-9]+)/\\1$" % got[0])
else:
    print("  ok: and that line does not satisfy the N/N gate "
          "('figures: 0/0' would have)")
if "figures:" not in err.getvalue():
    fails.append("the reason on stderr")
    print("FAIL: no reason on stderr: %r" % err.getvalue())
else:
    print("  ok: and says on stderr why it could not count it")
if rc != 1:
    fails.append("a malformed census must fail the gate")
    print("FAIL: exit %d — figures is blocking; unknown is not a pass" % rc)
else:
    print("  ok: figures is blocking — an unreadable census exits 1")

sys.exit(1 if fails else 0)
CENSUSPY
[ $? -eq 0 ] || bad "the figure census count"

echo
echo "== the id sequence: the consult contract's group and notes ids may be added =="
# Owner ruling 2026-09-28: the consult contract wins over the goal gate. A spec
# rewritten to put its items in a group and add the general-notes item keeps
# every original id in order; only those two kinds of id may appear on top.
# Layer: unit on corpus_diff.compare_body — the judge is a function of two
# bodies, no build and no browser needed.
python3 - "$HERE" "$tmp" <<'IDSPY'
import os, sys
sys.path.insert(0, sys.argv[1])
import corpus_diff
tmp = sys.argv[2]
fails = []

ORIG = ('<main><section class="consult-item" data-id="a"><h3>Uno</h3></section>'
        '<section class="consult-item" data-id="b"><h3>Dos</h3></section></main>')
page = os.path.join(tmp, "ids-orig.html")
with open(page, "w", encoding="utf-8") as fh:
    fh.write(ORIG)

A = '<section class="consult-item" data-id="a"><h3>Uno</h3></section>'
B = '<section class="consult-item" data-id="b"><h3>Dos</h3></section>'
NOTES = ('<section class="consult-item consult-notes" data-id="notes" '
         'data-title="Notas generales"><h3><span class="consult-id">notes</span>'
         'Notas generales</h3><textarea></textarea></section>')


def group(inner, gid="g", head=""):
    h = '<div class="sec-head"><h2>%s</h2></div>' % head if head else ""
    return ('<section class="consult-group" id="%s" data-id="%s">%s%s</section>'
            % (gid, gid, h, inner))


def case(label, body, expect, needle="", orig=None):
    target = page
    if orig is not None:
        target = os.path.join(tmp, "ids-orig-2.html")
        with open(target, "w", encoding="utf-8") as fh:
            fh.write("<main>%s</main>" % orig)
    ok, problems = corpus_diff.compare_body("<main>%s</main>" % body, target)
    if ok != expect or (needle and not any(needle in p for p in problems)):
        fails.append(label)
        print("FAIL: %s -> %r" % (label, problems))
    else:
        print("  ok: " + label)


case("the identical sequence is clean", A + B, True)
case("an added group id around the original items is clean", group(A + B), True)
case("an added notes item is clean, its title included", A + B + NOTES, True)
case("groups and notes together are clean", group(A) + group(B, "h") + NOTES, True)
case("reordered original ids fail", B + A, False, "ids differ")
case("reordered original ids inside an added group still fail", group(B + A), False,
     "ids differ")
case("a missing original id fails", A, False, "ids differ")
case("an added item id that is neither group nor notes fails",
     A + B + '<section class="consult-item" data-id="c"></section>', False,
     "ids differ")
case("an added group's heading is still compared as visible text",
     group(A + B, head="Consulta"), False, "visible text differs")
case("two added notes items fail: only one is the contract's",
     A + B + NOTES + NOTES.replace('"notes"', '"notes2"'), False, "ids differ")
case("a notes item the original already had is still compared",
     A + B + NOTES.replace("Notas generales", "Otra cosa"), False,
     "visible text differs", orig=A + B + NOTES)

# Option text (owner ruling 2026-09-28, extension): inside a consult option's
# label only, the " — " label/hint separator and the badge word the kit now
# draws itself ("Recomendada") are not compared. Everything else in the label is.
OLD_OPT = ('<label class="opt"><input type="radio" name="q" value="a">'
           '<span class="opt-name">Uno</span><span class="rec">Recomendada</span> '
           '<span class="opt-note">— el detalle — con guion</span></label>'
           '<label class="opt"><input type="radio" name="q" value="b">'
           '<span class="opt-name">Dos</span> <span class="opt-note">— otro</span></label>')


def opt(label, hint, rec=False):
    return ('<label><input type="radio" name="q" data-label="%s"%s><span>%s '
            '<span class="hint">%s</span></span></label>'
            % (label, " data-recommended" if rec else "", label, hint))


BUILT_OPTS = opt("Uno", "el detalle — con guion", True) + opt("Dos", "otro")
case("an option's separator and badge word match the built {recommended} option",
     BUILT_OPTS, True, orig=OLD_OPT)
case("the badge word outside an option is still text",
     "<p>Uno es la opción.</p>", False, "visible text differs",
     orig="<p>Uno es la opción. Recomendada</p>")
case("a dash outside an option is still text",
     "<p>Uno el detalle</p>", False, "visible text differs",
     orig="<p>Uno — el detalle</p>")
case("a hint word changed inside an option still fails",
     opt("Uno", "el detalle — sin guion", True) + opt("Dos", "otro"), False,
     "visible text differs", orig=OLD_OPT)

# corpus_html.BADGE_WORDS is a hand copy of the kit's `rec` strings, one per
# language: a language added to the composer, or a word changed there, would
# leave the old badge word in every converted option label as text.
import re
import corpus_html
with open(os.path.join(sys.argv[1], "..", "assets", "artifact-kit", "composer.js"),
          encoding="utf-8") as fh:
    kit_rec = set(re.findall(r"^\s*rec: '([^']+)',$", fh.read(), re.M))
if kit_rec and kit_rec == corpus_html.BADGE_WORDS:
    print("  ok: BADGE_WORDS is the composer's rec words")
else:
    fails.append("badge lockstep")
    print("FAIL: BADGE_WORDS %s != composer.js rec %s"
          % (sorted(corpus_html.BADGE_WORDS), sorted(kit_rec)))
sys.exit(1 if fails else 0)
IDSPY
[ $? -eq 0 ] || bad "the id-sequence rule"

echo
echo "== the frozen sample itself (test_corpus_sample.py) =="
sample_out="$(python3 "$HERE/test_corpus_sample.py" 2>&1)"
rc=$?
printf '%s\n' "$sample_out"
# With the real corpus set, a SKIP here would be a real-corpus case that
# silently stopped running.
if [ -n "$REAL" ]; then want_sample='^OK'; else want_sample='^(OK|SKIP)'; fi
check "test_corpus_sample.py exits 0 and says OK (or SKIP without a corpus)" \
  "$([ $rc -eq 0 ] && printf '%s' "$sample_out" | grep -qE "$want_sample" && echo 1 || echo 0)" \
  "exit $rc"

echo
if [ -n "$REAL" ]; then real_note="at $REAL"; else real_note="SKIPPED (AIDEX_SPEC_CORPUS not set)"; fi
if [ "$fails" -eq 0 ]; then
  echo "OK — goal-gate.sh: no corpus means exit 2 and no line; seven lines in the fixed order, every figure counted from the figure census on its assigned rung (and every malformed or non-covering census refusing to count), newly-fail blocking, the blind trial counted from its log (and every malformed log refusing to read 3/3), the naming rule, all four escape detectors (including the two no corpus page can fire), and the hand-advanced floor — on the synthetic corpus, and on the real one $real_note"
  exit 0
fi
echo "NOT OK — $fails failure(s)"
exit 1
