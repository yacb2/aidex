#!/usr/bin/env bash
# test-galleries-gate.sh — the logic of galleries_gate.py, with a FAKE probe (AIDEX_RENDER_PROBE, no
# browser) and the REAL builder on tiny fixtures, never the real defect count: the build rule per intent
# (valid / refusal-only), the frozen manifest (original first, migrated copy only while the original is
# refused, stale migration, nothing written into the manifest), each page condition firing on a crafted
# bad page (kit marker and styles, missing cell, tile count, distinct image CONTENT, image file, hidden
# image, visible caption, shared after-capture, undeclared section, zero cells), the probe verdict rule,
# its single call and its attribution per page, which image each tile shows, both halves of the pin (the
# generated half refused at import), the migration's expected refusal, the one-line stdout and the exit codes. Every
# cell was seen red against a mutated copy of the gate (GALLERIES_GATE_UNDER_TEST).
# Layer: script-level (stdlib Python driven from bash), because the contract is the CLI's.
# Run with: bash skills/artifact/tests/test-galleries-gate.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GATE="${GALLERIES_GATE_UNDER_TEST:-$HERE/galleries_gate.py}"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cells() { local out; out="$("$@" 2>&1)"; while IFS= read -r l; do
  case "$l" in "ok: "*) ok "${l#ok: }";; *) bad "$l";; esac; done <<<"$out"; }

echo "== units, builds, page conditions, probe, manifest, exit rule (python cells) =="
cells python3 - "$GATE" "$TMP" <<'PY'
import contextlib, importlib.util, io, os, re, shutil, subprocess, sys
gate, tmp = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.dirname(gate))
spec = importlib.util.spec_from_file_location("galleries_gate", gate)
gg = importlib.util.module_from_spec(spec)
sys.modules["galleries_gate"] = gg
spec.loader.exec_module(gg)

def check(cond, name, why=""):
    print(("ok: " if cond else "FAIL: ") + name + ("" if cond else " -- " + str(why)[:300]))

def script(name, body, mode=None):
    p = os.path.join(tmp, name)
    open(p, "w").write(body)
    if mode:
        os.chmod(p, mode)
    return p

def quiet(fn, *a, **k):
    with contextlib.redirect_stderr(io.StringIO()):
        return fn(*a, **k)

NOMANIFEST = os.path.join(tmp, "no-manifest")
units = quiet(gg.make_units, NOMANIFEST)
by_tag = {u["tag"]: u for u in units}
check(len({u["tag"] for u in units}) == len(units) and all(u["tag"].startswith("gen:") for u in units),
      "with no manifest the units are the generated set, tags unique")
check(all(c.build_files() == c.build_files() for c in gg.generated_cases()), "the generated set is deterministic")

# --- build rule per intent -----------------------------------------------------------------------
cb = gg.classify_build
TB = "Traceback (most recent call last):\n  File x\nValueError: boom"
check(cb(1, TB, False, False) == "traceback" and cb(0, TB, True, False) == "traceback", "a traceback fails even with exit 0")
check(cb(1, "x:1: `gallery` rows='r' was refused: nope", False, False) == "refused", "a named refusal is a refusal")
check(cb(1, "x", True, False) == "half-written" and cb(1, "x", False, True) == "half-written", "a refusal that left a page or residue is half-written")
check(cb(1, "  ", False, False) == "silent-refusal", "a refusal with no message fails")
check(cb(0, "Built", False, False) == "no-page" and cb(0, "Built", True, False) == "built", "exit 0 needs a page")
check(cb(-11, "", False, False) == "crashed", "a signal death is a crash")

one_valid, one_bad = by_tag["gen:rows1-en"], by_tag["gen:bad-no-look"]
def build(u, intent=None, builder=None, **over):
    old = gg.SPEC_BUILD
    if builder:
        gg.SPEC_BUILD = builder
    root = os.path.join(tmp, "b%d" % len(os.listdir(tmp)))
    os.makedirs(root)
    try:
        return gg.build_unit(root, 0, dict(u, intent=intent or u["intent"], **over))
    finally:
        gg.SPEC_BUILD = old
codes = lambda r: [c for c, _ in r["fails"]]
r = build(one_valid)
check(r["kind"] == "built" and r["page"] and not r["fails"], "a valid gallery builds into a page with no build failure", r["fails"])
r = build(one_bad)
check(r["kind"] == "refused" and not r["fails"] and r["page"] is None, "invalid input refused with a message naming the gallery block passes", r["fails"])
check(codes(build(one_bad, "valid")) == ["BUILD:valid-refused"], "the same refusal of an intended-VALID gallery is a failure")
check(codes(build(one_valid, "refusal-only")) == ["BUILD:refusal-only-built"], "invalid input that builds a page is a failure")
ref_other = script("b_ref.py", 'import sys\nsys.stderr.write("spec:3: some other problem\\n")\nsys.exit(1)\n')
check(codes(build(one_bad, builder=ref_other)) == ["BUILD:wrong-refusal"], "a refusal that does not name the gallery block fails")
check(codes(build(one_bad, builder=ref_other, expect="some other problem")) == [], "a case's own expected message is accepted")
tb = script("b_tb.py", 'import sys\nsys.stderr.write("Traceback (most recent call last):\\nValueError: boom\\n")\nsys.exit(1)\n')
check(codes(build(one_bad, builder=tb)) == ["BUILD:traceback"], "a traceback refusal fails")
half = script("b_half.py", 'import sys\nopen(sys.argv[sys.argv.index("-o")+1], "w").write("<html>")\nsys.stderr.write("late `gallery`\\n")\nsys.exit(1)\n')
check(codes(build(one_bad, builder=half)) == ["BUILD:half-written"], "a refusal that wrote a page fails")

# --- a builder that refuses everything must not read green ---------------------------------------
gg.SPEC_BUILD = ref_other
res = quiet(gg.measure, units)
check(sum(1 for _, f, _ in res if not f) == 0, "a builder that refuses every spec (without naming the gallery) passes nothing")
gg.SPEC_BUILD = script("b_gal.py", 'import sys\nsys.stderr.write("spec:3: `gallery` rows=\'x\' was refused: nope\\n")\nsys.exit(1)\n')
res = quiet(gg.measure, units)
passed = {u["tag"] for u, f, _ in res if not f}
check(passed == {u["tag"] for u in units if u["intent"] == "refusal-only" and u["expect"] == "`gallery`"},
      "a builder that refuses everything passes exactly the invalid-input cases that expect that message", sorted(passed))
gg.SPEC_BUILD = os.path.join(gg.SCRIPTS, "spec_build.py")

# --- page conditions, each on a crafted bad page -------------------------------------------------
def variant(built, name, text, copy=()):
    """A copy of a built unit's dir with the page replaced by `text` (and files copied beside it)."""
    d = os.path.join(tmp, "pg_" + name)
    shutil.copytree(built["dir"], d, symlinks=True)
    p = os.path.join(d, os.path.basename(built["page"]))
    open(p, "w", encoding="utf-8").write(text)
    for src, dst in copy:
        shutil.copyfile(os.path.join(d, src), os.path.join(d, dst))
    return p
def decl(built):
    return gg.declared_cells(open(os.path.join(built["dir"], "p.spec.md"), encoding="utf-8").read(), built["dir"])
good = build(by_tag["gen:rows5-en"])
D = decl(good)
html = open(good["page"], encoding="utf-8").read()
check(len(D[0]) == 5 and not D[2], "five declared cells are read from the rows file", D[2])
check(gg.check_page(good["page"], D) == [], "a real page built now passes every page condition", gg.check_page(good["page"], D))
def fires(name, text, code, d=D, built=good, copy=()):
    got = [c for c, _ in gg.check_page(variant(built, name, text, copy), d)]
    check(code in got, "page condition %s fires on %s" % (code, name), got)
ver = open(os.path.join(gg.KIT, "VERSION")).read().strip()
meta = '<meta name="artifact-kit" content="%s">' % ver
check(meta in html, "the kit marker is where the test expects it")
fires("no marker", html.replace(meta, ""), "KIT:marker")
fires("stale marker", html.replace(meta, '<meta name="artifact-kit" content="1">'), "KIT:marker")
fires("no tokens", html.replace(open(os.path.join(gg.KIT, "tokens.css")).read(), "/* own */"), "KIT:tokens.css")
fires("no components", html.replace(open(os.path.join(gg.KIT, "components.css")).read(), "/* own */"), "KIT:components.css")
first = D[0][0]["id"]
sec = re.search(r'<section class="consult-item consult-gallery"[^>]*data-id="%s".*?</section>' % re.escape(first), html, re.S).group(0)
fires("a cell removed", html.replace(sec, ""), "CELL:missing")
fig = re.search(r"<figure.*?</figure>", sec, re.S).group(0)
fires("a tile removed", html.replace(sec, sec.replace(fig, "", 1)), "CELL:tiles")
srcs = re.findall(r'<img src="([^"]+)"', sec)
fires("an image file gone", html.replace(sec, sec.replace(srcs[0], "rebuilt000-assets/gallery/gone.png")), "CELL:image")
cap = re.search(r"<figcaption>[^<]*</figcaption>", sec).group(0)
fires("an empty caption", html.replace(sec, sec.replace(cap, "<figcaption></figcaption>", 1)), "CELL:caption")
fires("a hidden caption", html.replace(sec, sec.replace(cap, "<figcaption hidden>x</figcaption>", 1)), "CELL:caption")
fires("a caption in a hidden wrapper", html.replace(sec, sec.replace(fig, '<div style="display: none">%s</div>' % fig, 1)), "CELL:caption")
img = re.search(r"<img [^>]*>", sec).group(0)
fires("an img with the hidden attribute", html.replace(sec, sec.replace(img, img.replace("<img ", "<img hidden ", 1), 1)), "CELL:image-hidden")
fires("an img styled display none", html.replace(sec, sec.replace(img, img.replace("<img ", '<img style="display: none" ', 1), 1)), "CELL:image-hidden")
fires("an img of width 0", html.replace(sec, sec.replace(img, re.sub(r'width="\d+"', 'width="0"', img), 1)), "CELL:image-hidden")
fires("a figure in a hidden wrapper", html.replace(sec, sec.replace(fig, '<div hidden>%s</div>' % fig, 1)), "CELL:image-hidden")
fires("a section nobody declared", html.replace('data-id="%s"' % first, 'data-id="stray-section"', 1), "CELL:undeclared")
# a section with no tiles that no row declares is not an undeclared GALLERY section
check("CELL:undeclared" not in [c for c, _ in gg.check_page(good["page"], D)], "declared sections are never undeclared")
one = (D[0][:1], D[1], D[2])
check(gg.check_page(variant(good, "subset", html), one) == [], "a subset of the declared cells still passes on a good page")

# distinct image CONTENT, on an alternatives row: same bytes under a different src is the same image
alt = build(by_tag["gen:long-alternatives"])
Da = decl(alt)
ahtml = open(alt["page"], encoding="utf-8").read()
check(gg.check_page(alt["page"], Da) == [], "a real alternatives page passes (three different images)", gg.check_page(alt["page"], Da))
asrc = re.findall(r'<img src="([^"]+)"', ahtml)
alt_dir = os.path.dirname(alt["page"])
check(len(asrc) == 3, "the alternatives row shows three tiles", asrc)
fires("two alternatives with the same bytes under another src", ahtml.replace(asrc[1], "rebuilt000-assets/gallery/dup.png"),
      "CELL:distinct", Da, alt, copy=[(os.path.join("rebuilt000-assets", "gallery", os.path.basename(asrc[0])), os.path.join("rebuilt000-assets", "gallery", "dup.png"))])
check("CELL:distinct" not in [c for c, _ in gg.check_page(variant(alt, "alt-ok", ahtml), Da)], "three different alternatives are not flagged")
# which image a tile shows: swapping two tiles' files keeps every count, name and distinct-content rule green
def swapped(built, name, a, b):
    """The built page's dir copied, the bytes of image files a and b (page-relative) exchanged."""
    d = os.path.dirname(variant(built, name, open(built["page"], encoding="utf-8").read()))
    pa, pb = os.path.join(d, a), os.path.join(d, b)
    da, db = open(pa, "rb").read(), open(pb, "rb").read()
    open(pa, "wb").write(db)
    open(pb, "wb").write(da)
    return os.path.join(d, os.path.basename(built["page"]))
def tile_src(page_html, rid, tile):
    s = re.search(r'data-id="%s".*?data-tile="%s"><img src="([^"]+)"' % (re.escape(rid), re.escape(tile)), page_html, re.S)
    return urllib.parse.unquote(s.group(1))
import urllib.parse
r0, r1 = D[0][0]["id"], D[0][1]["id"]
got = [c for c, _ in gg.check_page(swapped(good, "swap-after", tile_src(html, r0, "after"), tile_src(html, r1, "after")), D)]
check(got.count("CELL:content") == 2 and "CELL:distinct" not in got and "CELL:duplicate-after" not in got,
      "two rows' after-images exchanged (before/after of a pair, counts and distinctness intact) is CELL:content", got)
check("CELL:content" in [c for c, _ in gg.check_page(variant(good, "renamed-tile", html.replace('data-tile="after"', 'data-tile="zzz"', 1)), D)],
      "a tile the row does not declare (renamed data-tile) is CELL:content")
check(any("missing tile 'before'" in m for c, m in gg.check_page(variant(good, "after-twice", html.replace('data-tile="before"', 'data-tile="after"', 1)), D)),
      "a pair showing the after tile twice and no before tile names the missing tile")
check("CELL:content" in [c for c, _ in gg.check_page(swapped(alt, "swap-alt", asrc[0], asrc[1]), Da)],
      "two alternatives' images exchanged (captures[id]) is CELL:content")
st = build(by_tag["gen:states-row"])
Ds, shtml = decl(st), open(st["page"], encoding="utf-8").read()
check(gg.check_page(st["page"], Ds) == [], "a real states page passes", gg.check_page(st["page"], Ds))
check("CELL:content" in [c for c, _ in gg.check_page(swapped(st, "swap-st", tile_src(shtml, Ds[0][0]["id"], "empty"), tile_src(shtml, Ds[0][0]["id"], "loaded")), Ds)],
      "two states' images exchanged (states[i].capture) is CELL:content")
# an identical before/after pair is valid input ("unchanged"): never judged
same = build(by_tag["gen:identical-pair"])
check(same["kind"] == "built" and gg.check_page(same["page"], decl(same)) == [], "a before/after pair with identical bytes passes (it means unchanged)", gg.check_page(same["page"], decl(same)) if same["page"] else same["kind"])

# the same after capture in two rows of one gallery
def dup_unit(tag, **kw):
    c = gg.Case(tag, "valid")
    cap = c.cap()
    c.row("one", pair=False, after=cap)
    c.row("two", pair=False, **kw.get("two", {"after": cap}))
    return gg.case_unit(c)
d1 = build(dup_unit("dupafter"))
check([c for c, _ in gg.check_page(d1["page"], decl(d1))] == ["CELL:duplicate-after"], "two rows of one gallery sharing an after capture are flagged", gg.check_page(d1["page"], decl(d1)))
cu = gg.Case("dupbefore", "valid")
shared = cu.cap()
cu.row("one", before=shared)
cu.row("two", before=shared)
d2 = build(gg.case_unit(cu))
check(gg.check_page(d2["page"], decl(d2)) == [], "rows that share only a BEFORE capture are fine", gg.check_page(d2["page"], decl(d2)))

# two galleries on one page may share a capture: "one gallery" is the unit of the duplicate rule
two = gg.Case("twogal", "valid")
cap2 = two.cap()
two.row("one", pair=False, after=cap2)
tf = two.build_files()
tf["rows2.json"] = tf["rows.json"].replace(b'"gal"', b'"gal2"')
tf["p.spec.md"] = tf["p.spec.md"].replace(b'::: notes', b'::: gallery {#GB title="Second" rows="rows2.json" root="."}\n:::\n\n::: notes')
ut = dict(gg.case_unit(two), files=tf)
t2 = build(ut)
check(t2["kind"] == "built" and len(decl(t2)[0]) == 2 and gg.check_page(t2["page"], decl(t2)) == [],
      "the same after capture in two DIFFERENT galleries is not a duplicate", gg.check_page(t2["page"], decl(t2)) if t2["page"] else t2["kind"])

# the spec is read by the builder's own parser: unquoted attrs, zero cells, unreadable rows
spec_text = open(os.path.join(good["dir"], "p.spec.md"), encoding="utf-8").read()
unq = re.sub(r'::: gallery \{#GA title="[^"]*" rows="rows.json" root="."\}', '::: gallery {#GA title=Shots rows=rows.json root=.}', spec_text)
check(unq != spec_text and len(gg.declared_cells(unq, good["dir"])[0]) == 5, "a gallery fence with unquoted attrs still declares its cells", len(gg.declared_cells(unq, good["dir"])[0]))
alldrop = os.path.join(tmp, "alldrop"); os.makedirs(alldrop)
open(os.path.join(alldrop, "rows.json"), "w").write('{"gallery":"g","variants":["light-desktop"],"rows":[{"cell":"x","variant":"light-desktop","kind":"review","dropped":"gone"},{"cell":"y","notApplicable":"none"}]}')
z = gg.declared_cells(spec_text, alldrop)
check(z[0] == [] and [c for c, _ in z[2]] == ["CELL:none"], "a gallery whose rows are all dropped or not applicable declares zero cells: CELL:none", z)
z2 = gg.declared_cells(spec_text.replace('rows="rows.json"', 'rows="absent.json"'), good["dir"])
check([c for c, _ in z2[2]] == ["CELL:none"], "an unreadable rows file is CELL:none, not a silent skip", z2)
check("CELL:none" in [c for c, _ in gg.check_page(good["page"], z)], "check_page reports the zero-cell problem")
dr = gg.declared_cells(spec_text.replace("::: masthead {", '::: masthead {dropped-ids="%s" ' % D[0][0]["id"], 1), good["dir"])
check([c["id"] for c in dr[0]] == [c["id"] for c in D[0][1:]], "a cell the masthead drops (dropped-ids) is not a declared cell", [c["id"] for c in dr[0]])
nad = build(by_tag["gen:na-and-dropped"])
na = decl(nad)
check(len(na[0]) == 1 and len(na[1]) == 3, "a notApplicable or dropped row is not a shown cell but is a declared id", (len(na[0]), len(na[1])))
check(gg.declared_tiles({"before": "a", "after": "b"}) == 2 and gg.declared_tiles({"after": "b"}) == 1
      and gg.declared_tiles({"captures": {"x": "p", "y": {"s": "q", "t": "r"}}}) == 3
      and gg.declared_tiles({"states": [1, 2, 3]}) == 3, "declared_tiles counts before/after, alternatives (and their states) and states")

# --- the probe: one call, the verdict rule, attribution, every message --------------------------
calllog = os.path.join(tmp, "calls")
def fake(name, body):
    p = script(name, '#!/usr/bin/env bash\necho "$#" >> "%s"\nshift\n%s\n' % (calllog, body), 0o755)
    gg.PROBE = p
three = [by_tag[t] for t in ("gen:rows1-en", "gen:rows5-en", "gen:sample-only")]
fake("p_clean.sh", 'echo "INVARIANTS pages=$# violations=0"')
res = quiet(gg.measure, three)
check([f for _, f, _ in res] == [[], [], []], "built pages with a clean probe pass", res)
check(open(calllog).read().split() == ["4"], "all built pages go through ONE probe call", open(calllog).read())
fake("p_flag0.sh", 'echo "INV NAV-4 rebuilt000.html label x"\necho "INVARIANTS pages=$# violations=1"; exit 1')
res = quiet(gg.measure, three)
check([[c for c, _ in f] for _, f, _ in res] == [["INV:NAV-4"], [], []], "a violation on page 0 fails unit 0 only", [f for _, f, _ in res])
fake("p_all.sh", 'echo "INV A-1 rebuilt000.html one"; echo "INV A-1 rebuilt000.html two"; echo "INV B-2 rebuilt000.html three"\necho "INVARIANTS pages=$# violations=3"; exit 1')
res = quiet(gg.measure, three[:1])
check(sorted(d for _, d in res[0][1]) == ["one", "three", "two"], "every message of every invariant on a page is kept, not only the first", res[0][1])
fake("p_silent.sh", "exit 0")
res = quiet(gg.measure, three[:1])
check([x for x, _ in res[0][1]] == ["PROBE:no-verdict"], "a probe with no verdict fails the page it should have judged")
fake("p_rc0.sh", 'echo "INV NAV-4 rebuilt000.html a"; echo "INVARIANTS pages=$# violations=1"; exit 0')
res = quiet(gg.measure, three[:1])
check([x for x, _ in res[0][1]] == ["PROBE:no-verdict"], "exit 0 with violations is no verdict")
fake("p_crash.sh", "echo boom >&2; exit 4")
res = quiet(gg.measure, three[:1])
check([x for x, _ in res[0][1]] == ["PROBE:no-verdict"], "a crashed probe fails the page")

# --- the manifest: original first, migrated copy only while the original is refused ---------------
def manifest(root, name, bad_spec, good_spec=None):
    """root/<name>/ = a tiny gallery unit (spec.md, rows, root/shots); root/migrated/<name>/ = good_spec."""
    def write(d, spec_text):
        os.makedirs(os.path.join(d, "root", "shots"), exist_ok=True)
        open(os.path.join(d, "spec.md"), "w").write(spec_text)
        open(os.path.join(d, "ORIGIN"), "w").write("/somewhere/%s.spec.md\n" % name)
        open(os.path.join(d, "root", "shots", "a.png"), "wb").write(gg.png(1))
        open(os.path.join(d, "root", "shots", "b.png"), "wb").write(gg.png(2))
        open(os.path.join(d, "rows.json"), "w").write('{"gallery":"g","variants":["light-desktop"],"rows":[{"cell":"one","variant":"light-desktop","kind":"review","look":"x","before":"shots/a.png","after":"shots/b.png"}]}')
    write(os.path.join(root, name), bad_spec)
    if good_spec is not None:
        write(os.path.join(root, "migrated", name), good_spec)
base = ('::: masthead {eyebrow="e" lang="en" title="T" visual="none: x"}\nIntro.\n:::\n\n'
        '::: group {#G1 title="D" heading="D"}\n::: item {#Q1 title="Which?"}\nPick.\n\n%s:::\n:::\n\n'
        '::: gallery {#GA title="Shots" rows="rows.json" root="root"}\n:::\n\n::: notes {#notes title="Notes"}\n:::\n')
OK_OPTS, OLD_OPTS = "- A {recommended}\n- B\n", "- A (the old way) {recommended}\n- B\n"
def tree(d):
    return sorted((os.path.join(dp, f), os.path.getmtime(os.path.join(dp, f))) for dp, _, fs in os.walk(d) for f in fs) \
        + sorted(os.path.join(dp, x) for dp, ds, _ in os.walk(d) for x in ds)
fake("p_clean3.sh", 'echo "INVARIANTS pages=$# violations=0"')
PAREN = "carries a parenthetical"
gg.MIGRATED_EXPECT = {"refused-one": PAREN, "resid": PAREN, "tb": PAREN}
m1 = os.path.join(tmp, "man1")
manifest(m1, "refused-one", base % OLD_OPTS, base % OK_OPTS)
manifest(m1, "builds-one", base % OK_OPTS, base % OK_OPTS)
manifest(m1, "refused-alone", base % OLD_OPTS)
mu = quiet(gg.manifest_units, m1)
check([u["tag"] for u in mu] == ["disk:builds-one", "disk:refused-alone", "disk:refused-one"], "manifest units are the galleries/<name> dirs, not migrated/", [u["tag"] for u in mu])
check([bool(u["alt"]) for u in mu] == [True, False, True], "a migrated copy is attached to its original by name")
check(all(u["source"] == "/somewhere/%s.spec.md" % u["tag"][5:] and "--only %s " % u["tag"] in u["replay"] and "--verbose" in u["replay"] for u in mu),
      "a manifest unit names its ORIGIN as source and replays with --only disk:<name> --verbose", mu[0])
before = tree(m1)
err = io.StringIO()
with contextlib.redirect_stderr(err):
    res = gg.measure(mu)
by = {u["tag"]: (f, m) for u, f, m in res}
check(by["disk:refused-one"] == ([], True), "an original refused by today's builder is measured from its migrated copy (flagged migrated)", by["disk:refused-one"])
check(by["disk:builds-one"] == ([], False), "an original that builds is used as it is", by["disk:builds-one"])
check("stale migration: disk:builds-one" in err.getvalue() and "stale migration: disk:refused-one" not in err.getvalue(),
      "a migrated copy beside an original that builds prints `stale migration`", err.getvalue())
check([c for c, _ in by["disk:refused-alone"][0]] == ["BUILD:valid-refused"] and by["disk:refused-alone"][1] is False,
      "an original refused with no migrated copy is a failure", by["disk:refused-alone"])
check(tree(m1) == before, "measuring the manifest writes nothing into it")
m2 = os.path.join(tmp, "man2")
manifest(m2, "stale-too", base % OK_OPTS, base % OLD_OPTS)
res = quiet(gg.measure, quiet(gg.manifest_units, m2))
check(res[0][1] == [] and res[0][2] is False, "a stale migrated copy (even a broken one) is ignored", res)
m3 = os.path.join(tmp, "man3")
manifest(m3, "gone", base % OK_OPTS)
shutil.rmtree(os.path.join(m3, "gone", "root", "shots"))
res = quiet(gg.measure, quiet(gg.manifest_units, m3))
check([c for c, _ in res[0][1]] == ["BUILD:source-missing"], "a missing capture is reported as source-missing, still a failure", res[0][1])

# an original refused for ANOTHER reason than the one recorded is a failure naming it, never a fallback
for nm, table in (("other-reason", {"other-reason": "has no 'look' line"}), ("unrecorded", {})):
    gg.MIGRATED_EXPECT = table
    mx = os.path.join(tmp, "man_" + nm)
    manifest(mx, nm, base % OLD_OPTS, base % OK_OPTS)
    res = quiet(gg.measure, quiet(gg.manifest_units, mx))
    check("BUILD:new-refusal" in [c for c, _ in res[0][1]] and res[0][2] is False and "parenthetical" in " ".join(d for _, d in res[0][1]),
          "an original refused for a reason the migration does not record (%s) fails as new-refusal and names the reason" % nm, res[0][1:])
gg.MIGRATED_EXPECT = {"tb": PAREN, "resid": PAREN}
# only a REFUSAL falls back to the migrated copy; the corpus's own residue never counts against a build
tbk = script("b_oldtb.py", 'import subprocess, sys\nif "(the old way)" in open(sys.argv[1]).read():\n    sys.stderr.write("Traceback (most recent call last):\\nValueError: boom\\n"); sys.exit(1)\nsys.exit(subprocess.call([sys.executable, "%s"] + sys.argv[1:]))\n' % os.path.join(gg.SCRIPTS, "spec_build.py"))
m5 = os.path.join(tmp, "man5")
manifest(m5, "tb", base % OLD_OPTS, base % OK_OPTS)
gg.SPEC_BUILD = tbk
res = quiet(gg.measure, quiet(gg.manifest_units, m5))
gg.SPEC_BUILD = os.path.join(gg.SCRIPTS, "spec_build.py")
check([c for c, _ in res[0][1]] == ["BUILD:traceback"] and res[0][2] is False, "an original that crashes is a failure, never replaced by its migrated copy", res[0][1:])
m6 = os.path.join(tmp, "man6")
manifest(m6, "resid", base % OLD_OPTS, base % OK_OPTS)
os.makedirs(os.path.join(m6, "resid", ".aidex-artifact-prev"))
open(os.path.join(m6, "resid", ".aidex-artifact-prev", "old.html"), "w").write("old")
res = quiet(gg.measure, quiet(gg.manifest_units, m6))
check(res[0][1] == [] and res[0][2] is True, "residue left in the manifest by an old build does not turn a clean refusal into half-written", res[0][1:])

# two manifest units, the probe flags page 0 only: exactly one fails
m4 = os.path.join(tmp, "man4")
manifest(m4, "aa", base % OK_OPTS)
manifest(m4, "bb", base % OK_OPTS)
fake("p_flag0b.sh", 'echo "INV NAV-4 rebuilt000.html label x"\necho "INVARIANTS pages=$# violations=1"; exit 1')
res = quiet(gg.measure, quiet(gg.manifest_units, m4))
check([(u["tag"], [c for c, _ in f]) for u, f, _ in res] == [("disk:aa", ["INV:NAV-4"]), ("disk:bb", [])],
      "two manifest units with one probe call: a violation on page 0 fails exactly one of them", [(u["tag"], f) for u, f, _ in res])

# --- the census: a live walk on stderr, never a failure ------------------------------------------
proj = os.path.join(tmp, "projects")
def put(rel, text="x\n"):
    p = os.path.join(proj, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(text)
    return p
G = '::: gallery {#GA title="G" rows="rows.json"}\n:::\n'
a = put("alpha/.context/art/a.spec.md", G)
put("alpha/.context/art/plain.spec.md", "::: masthead {title=\"x\"}\n:::\n")
put("alpha/node_modules/pkg/n.spec.md", G)
put("alpha/.git/g.spec.md", G)
put("aidex_ws/aidex/skills/z.spec.md", G)
put("aidex_ws/_tmp/wt/q/z.spec.md", G)
b = put("aidex_ws/.context/reports/r.spec.md", G)
put("alpha/notes.md", G)
check(sorted(p for _, p in gg.on_disk_specs(proj)) == sorted([a, b]),
      "the census finds specs with a gallery block and skips node_modules, .git, aidex_ws/aidex, aidex_ws/_tmp and non-specs", gg.on_disk_specs(proj))
old = gg.PROJECTS
gg.PROJECTS = proj
err = io.StringIO()
with contextlib.redirect_stderr(err):
    gg.census(m4, True)
gg.PROJECTS = old
check("2 gallery spec(s) on disk not in the manifest" in err.getvalue() and a in err.getvalue(), "the census says how many gallery specs the manifest does not hold", err.getvalue())

# --- the exit rule, the one stdout line, the pin ---------------------------------------------------
def run_main(argv, fails=(), n=None, migrated=0):
    n = gg.PINNED if n is None else n
    fake_units = [{"tag": "t%d" % i, "intent": "valid", "source": "s", "replay": "r"} for i in range(n)]
    real = (gg.make_units, gg.measure, gg.census)
    gg.make_units = lambda mdir, only="": fake_units
    gg.measure = lambda units: [(u, [("INV:X", "m")] if i in fails else [], i < migrated) for i, u in enumerate(units)]
    gg.census = lambda mdir, verbose: None
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(io.StringIO()):
            rc = gg.main(argv)
    finally:
        gg.make_units, gg.measure, gg.census = real
    return rc, buf.getvalue()
Y = gg.PINNED
check(run_main([]) == (0, "galleries: %d/%d\n" % (Y, Y)), "all pass at the pinned count exits 0 with exactly one stdout line", run_main([]))
check(run_main([], migrated=3) == (0, "galleries: %d/%d (3 migrated)\n" % (Y, Y)), "migrated units are counted on the line", run_main([], migrated=3))
check(run_main([], fails=(3,)) == (1, "galleries: %d/%d\n" % (Y - 1, Y)), "one failing unit exits 1", run_main([], fails=(3,)))
check(run_main([], n=Y + 1) == (1, "galleries: %d/%d (pin %d)\n" % (Y + 1, Y + 1, Y)), "X == Y above the pin exits 1 and names the pin", run_main([], n=Y + 1))
check(run_main([], n=Y - 1) == (1, "galleries: %d/%d (pin %d)\n" % (Y - 1, Y - 1, Y)), "X == Y below the pin exits 1 and names the pin", run_main([], n=Y - 1))
check(run_main(["--verbose"], fails=(0, 1)) == (1, "galleries: %d/%d\n" % (Y - 2, Y)), "--verbose adds nothing to stdout")
check(run_main(["--expected"]) == (0, "%d\n" % Y), "--expected prints the pinned count and exits 0")
# the generated half of Y is a literal checked at import: a case dropped or added refuses the gate (rc != 0, no stdout)
src = open(gate).read()
src = src.replace("HERE = os.path.dirname(os.path.abspath(__file__))", "HERE = %r" % os.path.dirname(os.path.abspath(gate)), 1)
drop = '    c = new("bad-unknown-dependency", "refusal-only")\n    c.row("waits", depends_on="Q99")\n'
add = '    c = new("one-more")\n    c.row("x")\n'
for what, mutated in (("dropped", src.replace(drop, "", 1)), ("added", src.replace("    return cases\n", add + "    return cases\n", 1))):
    assert mutated != src
    mp = script("gate_%s.py" % what, mutated)
    r = subprocess.run([sys.executable, mp, "--expected"], capture_output=True, text=True)
    check(r.returncode != 0 and r.stdout == "" and "GENERATED_PIN" in r.stderr and "Traceback" not in r.stderr,
          "a generated case %s refuses the gate loudly: GENERATED_PIN is a literal, not len(generated_cases())" % what, (r.returncode, r.stdout, r.stderr))
PY

echo "== the CLI: one stdout line, stderr carries the detail =="
printf '#!/usr/bin/env bash\nshift\necho "INVARIANTS pages=$# violations=0"; exit 0\n' > "$TMP/probe-clean.sh"; chmod +x "$TMP/probe-clean.sh"
mkdir -p "$TMP/noprojects" "$TMP/nomanifest"
AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" AIDEX_GALLERIES_PROJECTS="$TMP/noprojects" AIDEX_GALLERIES_MANIFEST="$TMP/nomanifest" python3 "$GATE" --verbose >"$TMP/out" 2>"$TMP/err"; rc=$?
[[ "$(wc -l <"$TMP/out")" -eq 1 && "$(cat "$TMP/out")" =~ ^galleries:\ [0-9]+/[0-9]+\ \(pin\ [0-9]+\)$ ]] && ok "stdout is exactly one line: galleries: X/Y (pin P) when the manifest is empty" || bad "stdout: $(cat "$TMP/out")"
[[ $rc -eq 1 ]] && ok "an empty manifest exits 1 (below the pin), never green" || bad "exit $rc"
# The failing unit is injected by the probe, so this check does not depend on the builder having a red.
printf '#!/usr/bin/env bash\nshift\necho "INV NAV-4 rebuilt000.html label x"; echo "INVARIANTS pages=$# violations=1"; exit 1\n' > "$TMP/probe-flag.sh"; chmod +x "$TMP/probe-flag.sh"
AIDEX_RENDER_PROBE="$TMP/probe-flag.sh" AIDEX_GALLERIES_PROJECTS="$TMP/noprojects" AIDEX_GALLERIES_MANIFEST="$TMP/nomanifest" python3 "$GATE" --verbose >/dev/null 2>"$TMP/err-flag"
grep -q "INV:NAV-4" "$TMP/err-flag" && grep -q "replay:" "$TMP/err-flag" && grep -q "source:" "$TMP/err-flag" && ok "--verbose names each failing gallery with source, reason and replay command" || bad "stderr: $(head -20 "$TMP/err-flag")"
grep -q "0 gallery spec(s) on disk not in the manifest" "$TMP/err" && ok "the census line is on stderr" || bad "no census: $(head -5 "$TMP/err")"
! grep -q "Traceback" "$TMP/err" && ok "no traceback from the gate itself" || bad "traceback on stderr"
AIDEX_RENDER_PROBE="$TMP/probe-clean.sh" AIDEX_GALLERIES_PROJECTS="$TMP/noprojects" AIDEX_GALLERIES_MANIFEST="$TMP/nomanifest" python3 "$GATE" --only gen:bad-json >"$TMP/out" 2>/dev/null; rc=$?
[[ "$(cat "$TMP/out")" == "galleries: 1/1 (pin "*")" && $rc -eq 1 ]] && ok "--only measures one unit (replay) and still fails the pin check" || bad "--only: $(cat "$TMP/out") rc=$rc"
[[ "$(python3 "$GATE" --expected)" =~ ^[0-9]+$ ]] && ok "--expected prints one number" || bad "--expected"

echo
echo "galleries-gate tests: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
