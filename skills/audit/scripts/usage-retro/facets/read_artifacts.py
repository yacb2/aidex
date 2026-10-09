#!/usr/bin/env python3
"""read_artifacts.py — the residue reader of the `artifacts` facet.

This folder is NOT a package on purpose: a `facets/__init__.py` next to `facets.py`
shadows the spec loader on import (a package dir wins over a module of the same
name), so every reader here is a standalone script that adds its parent to sys.path.

Walks every dated artifact page under `<projects-root>/*/.context/` — the SAME set
`mine_items.page_files` joins to sessions, active and `_archive/` alike — and reports
what the pages themselves say: kit version, consult round, items and how many are
decided, the round the consultation reached every item in (`data-decided-round`,
stamped per item by the wrapper since BL-421 — `unknown` on a page written before
it), and the verdict of `check-artifact.sh` run on each file.

Grouped by kit VERSION BAND on purpose: `check-artifact.sh --census` skips `_archive/`
and `.aidex-artifact-prev/` by design (the census is the quality gate for pages
being edited, not an instrument), and a v9 page failing a v18 rule is a finding about
v9–v12 pages, never "pages fail". The checker runs per file here for that reason.

A failure line carries the page's own date and grades itself against the date the
check became a rule (`SINCE`): `predates-rule` or `defect`. Deciding that took an
ad-hoc re-run over 88 pages the first time (BL-385). Because the run is per file, a
check the census only WARNS about (`CENSUS_ADVISORY`, imported from the checker) is
demoted on an `_archive/` page — the page the census itself skips.

Prints `pages processed: N` LAST, always — a reader that saw nothing must say 0.

usage: read_artifacts.py --projects-root DIR [--checker PATH]
"""
import os, re, sys, glob, argparse, subprocess, collections, datetime, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import mine_items  # noqa: E402  (page_files, add_root_args)

CHECKER = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "artifact",
                                        "scripts", "check-artifact.sh"))
META = re.compile(r'<meta\s+name=["\']?(artifact-kit|consult-round)["\']?\s+content=["\']?(\d+)', re.I)
# An item is an OPEN TAG carrying `data-id`, and only such a tag can be decided:
# the kit CSS (`.consult-item[data-decided]`) and the composer script
# (`hasAttribute('data-decided')`) mention the token on every page (BL-386).
# A quoted attribute value may hold a raw ">" (`data-decided="A -> keep"`), so the
# scan steps over whole quoted values; a quote opens a value only right after `=`.
# The same construction as check_artifact.py's _TAG_BYTES (BL-734 U1-1).
_TAG_BYTES = (r'(?:[^>="\']|=\s*"[^"]*"|=\s*\'[^\']*\''
              r'|=(?!\s*["\'])|["\'])*')
ITEM = re.compile(r'<[a-zA-Z][\w:-]*\b' + _TAG_BYTES + r'?\bdata-id\s*=' + _TAG_BYTES + '>',
                  re.I | re.S)
# `\b` after "decided" is satisfied by the hyphen of `data-decided-round`, so the
# bare pattern reads the STAMP as the mark. An item carries both; the two are read
# apart here so a page that somehow carries only the stamp is not called decided.
DECIDED = re.compile(r'\bdata-decided\b(?!-)', re.I)
# A QUESTION, which is not every `data-id` tag. A block carries `data-id` so the
# id-stability rule can hold it (`.consult-group`) and is a context, never a claim;
# `notes` is the one item the contract mandates on every page and it is answered,
# not decided. Counting either holds every real page at "not all decided" — it did,
# on 43 of 43 pages on disk. The predicate is check_artifact.py's own: its
# `consult_items()` skips the group class, and its still-asked rule skips `notes`.
# Mirrored rather than "a tag whose class says consult-item", so a page that never
# spelled the class still has its questions read.
GROUP = re.compile(r'\bclass\s*=\s*["\'][^"\']*\bconsult-group\b', re.I)
ITEM_ID = re.compile(r'\bdata-id\s*=\s*(?:"([^"]*)"|\'([^\']*)\'|([^\s>]+))', re.I)
DECIDED_ROUND = re.compile(
    r'\bdata-decided-round\s*=\s*(?:"(\d+)"|\'(\d+)\'|(\d+))', re.I)
FAIL = re.compile(r'^\s*FAIL \[([^\]]+)\]', re.M)
PAGE_DATE = re.compile(r'^(\d{4})-(\d{2})-(\d{2})-')

# When each check became a rule, from the commit that introduced it (BL-385). A page
# written before its check existed fails a rule that did not exist yet; calling that a
# defect is what made the first facet run unreadable. The `envelope` group of the
# backlog item is not one check name — the checker prints those checks individually,
# and 12c7649 (2026-07-24) is the commit that created the checker, so every check it
# was born with shares that date.
SINCE = {
    "doctype": "2026-07-24", "charset": "2026-07-24", "viewport": "2026-07-24",
    "title": "2026-07-24", "themes": "2026-07-24", "self": "2026-07-24",
    "siblings": "2026-07-24", "missing": "2026-07-24",
    "consult": "2026-08-17", "consult-ids": "2026-08-17",
    "layout": "2026-08-19",
    "consult-shape": "2026-08-27",
    "lang": "2026-08-31",
    "svg-contrast": "2026-09-07",
    "rail": "2026-09-14",          # ad5ec00
    "double-wrap": "2026-09-20",   # c5f20ee
    "gallery": "2026-09-22",       # the gallery row, plan phase 1
    "raw-link": "2026-09-25",      # a4dcc72, artifact-quality phase 5
    "rec-leak": "2026-09-27",      # BL-481
    "contract": "2026-09-28",      # contract_defects blocking in check-artifact, LOOP-006
}
# contract_defects' classes report under their own slugs, blocking since the same
# merge; read from the module, so a class added there is dated here without a copy.
sys.path.insert(0, os.path.join(os.path.dirname(CHECKER), "dash"))
import contract_defects  # noqa: E402
SINCE.update(dict.fromkeys(contract_defects.CHECKS, SINCE["contract"]))


def page_date(path):
    """`YYYY-MM-DD` from the basename, or None when those digits are not a real
    date. `mine_items.PAGE` already refuses a page without the prefix, so the only
    dateless page that reaches here is one whose digits do not form a date
    (`2026-13-45-x.html`) — it is reported `undated` and, below, graded `defect`:
    a page that cannot say when it was written cannot claim to predate anything."""
    m = PAGE_DATE.match(os.path.basename(path))
    if not m:
        return None
    try:
        return datetime.date(*(int(g) for g in m.groups())).isoformat()
    except ValueError:
        return None


def questions(tags):
    """The item tags that are QUESTIONS: no block, no mandatory notes item."""
    out = []
    for t in tags:
        m = ITEM_ID.search(t)
        ident = next((g for g in m.groups() if g is not None), "") if m else ""
        if not GROUP.search(t) and ident != "notes":
            out.append(t)
    return out


def decided_round(tags):
    """The round at which EVERY item of the page was decided, as a label.

    Over the page's QUESTIONS (`questions()`), never every `data-id` tag.

    Four states, and they are not one number: `no-items` (a read page, nothing to
    decide — vacuously "all decided" is the answer that would make a rounds
    histogram count read pages as round 0), `not-all-decided` (the consultation is
    still open — the max over the decided ones is not the round it will finish
    in), `unknown` (decided items that carry no `data-decided-round`: every page
    wrapped before BL-421, which must never be reported as round 0 or round 1),
    and the max of the stamps, which is the round the last item was decided in.
    """
    tags = questions(tags)
    if not tags:
        return "no-items"
    decided = [t for t in tags if DECIDED.search(t)]
    if len(decided) < len(tags):
        return "not-all-decided"
    rounds = []
    for t in decided:
        m = DECIDED_ROUND.search(t)
        if not m:
            return "unknown"
        rounds.append(int(next(g for g in m.groups() if g is not None)))
    return str(max(rounds))


def verdict(check, date):
    """`predates-rule` only when the page is STRICTLY older than the check's since
    date: a page written the day the rule landed had the rule, so the boundary day
    is a `defect`. A check absent from SINCE is a `defect` too — the map is the only
    evidence the rule is younger than the page, and without it there is none."""
    since = SINCE.get(check)
    if since is None:
        return "defect", "no since date"
    if date is not None and date < since:
        return "predates-rule", f"since {since}"
    return "defect", f"since {since}"


def census_advisory(checker):
    """The checks the CHECKER itself grades as advisory in `--census` — imported,
    never restated here. The checker has no per-file census mode, so an archived
    page is checked per file and these findings are demoted afterwards.

    The module is found by string surgery on a path the caller controls, so it can
    fail for reasons that have nothing to do with the tree being read: `--checker`
    is a stub, a wrapper somewhere else, not a file at all. A reader must still
    read — it says on stderr that nothing will be demoted, and walks the pages."""
    mod = os.path.join(os.path.dirname(os.path.abspath(checker)), "dash",
                       "check_artifact.py")
    try:
        # check_artifact imports its sibling contract_defects by name, which a
        # script run finds on sys.path[0]; a module loaded from a path does not.
        if os.path.dirname(mod) not in sys.path:
            sys.path.insert(0, os.path.dirname(mod))
        spec = importlib.util.spec_from_file_location("check_artifact_for_reader", mod)
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        return tuple(m.CENSUS_ADVISORY)
    except Exception as e:                          # noqa: BLE001 — advisory
        print(f"note: no census-advisory list next to the checker ({e}) — "
              f"nothing demoted on archived pages", file=sys.stderr)
        return ()


def read_page(path, ctx, checker, advisory_checks):
    txt = open(path, errors="replace").read()
    meta = {k.lower(): int(v) for k, v in META.findall(txt)}
    band = f"v{meta['artifact-kit']}" if "artifact-kit" in meta else "pre-wrapper"
    r = subprocess.run(["bash", checker, path], capture_output=True, text=True)
    tags = ITEM.findall(txt)
    # RELATIVE to the page's own `.context/`: what archives a page is where it sits
    # under that directory, and a project (or any ancestor of the projects root)
    # named `_archive` archives nothing. Against the absolute path this decided a
    # SEVERITY, which is exactly where such a coincidence must not be read.
    archived = "_archive" in os.path.relpath(path, ctx).split(os.sep)
    fails = sorted(set(FAIL.findall(r.stdout)))
    # An archived page is exactly the page the census leaves alone, so a check the
    # census only warns about must not make it count as failing here either.
    advisory = [c for c in fails if archived and c in advisory_checks]
    fails = [c for c in fails if c not in advisory]
    return {
        "path": path, "band": band, "version": meta.get("artifact-kit", 0),
        "round": meta.get("consult-round", 0), "date": page_date(path),
        # The band table's `items`/`decided` stay the RAW census of `data-id` tags
        # that carry the mark — what the pages say, which is what the version-band
        # rows have always counted. The question set is the narrower thing, so it
        # is reported next to the verdict it belongs to and labelled, rather than
        # silently re-pointing a column two other assertions read.
        "items": len(tags), "decided": sum(1 for t in tags if DECIDED.search(t)),
        "questions": len(questions(tags)),
        "questions_decided": sum(1 for t in questions(tags) if DECIDED.search(t)),
        "decided_round": decided_round(tags),
        "archived": archived,
        # The checker's EXIT CODE is the verdict; demotion is the only thing that
        # overrides it. A checker that dies without printing a parseable
        # `FAIL [check]` — a traceback, a usage error, no interpreter — leaves the
        # page unjudged, and `not fails` would have called that page ok.
        "ok": r.returncode == 0 or (bool(advisory) and not fails),
        "fails": fails, "advisory": advisory,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mine_items.add_root_args(ap)
    ap.add_argument("--checker", default=CHECKER, help="check-artifact.sh to run per page")
    args = ap.parse_args()
    mine_items.configure(args)
    mine_items.require_projects_root()

    advisory_checks = census_advisory(args.checker)
    pages = []
    for ctx in sorted(glob.glob(os.path.join(mine_items.PROJ_ROOT, "*", ".context"))):
        for f in mine_items.page_files(ctx):
            pages.append(read_page(f, ctx, args.checker, advisory_checks))

    bands = collections.defaultdict(list)
    for p in pages:
        bands[(p["version"], p["band"])].append(p)
    print("band          pages  archived  consult  items  decided  checker-ok")
    for (_, band), ps in sorted(bands.items()):
        print(f"{band:<13} {len(ps):>5}  {sum(p['archived'] for p in ps):>8}  "
              f"{sum(1 for p in ps if p['round']):>7}  {sum(p['items'] for p in ps):>5}  "
              f"{sum(p['decided'] for p in ps):>7}  {sum(p['ok'] for p in ps):>10}")

    # The round each page reached, not just how many pages carry one — and, since
    # BL-421, the round the consultation DECIDED everything in: the wrapper stamps
    # `data-decided-round` on an item when it is decided, so the two numbers are the
    # rounds the page took and the round it finished. `decided-round` is a label,
    # never a bare number: `unknown` is what a page written before the stamp says,
    # and reading that as round 0 or 1 is the finding the facet would invent.
    for p in sorted(pages, key=lambda p: p["path"]):
        if p["round"]:
            print(f"round {p['round']}: {p['path']} ({p['band']}, "
                  f"{p['questions_decided']}/{p['questions']} questions decided, "
                  f"decided-round {p['decided_round']})")

    # One line per failing (page, check), carrying the page's own date and the
    # verdict against the check's since date, so predates-rule vs defect is read
    # off the run instead of reconstructed by an ad-hoc re-run (BL-385).
    for p in sorted(pages, key=lambda p: p["path"]):
        for c in p["fails"]:
            label, since = verdict(c, p["date"])
            print(f"fail [{c}] {p['date'] or 'undated'} {label} ({since}): {p['path']}")
        for c in p["advisory"]:
            print(f"advisory [{c}] {p['date'] or 'undated'} (census severity, "
                  f"archived): {p['path']}")

    # Which versions fail which check: the band range is the finding's subject.
    by_check = collections.defaultdict(set)
    for p in pages:
        for c in p["fails"]:
            by_check[c].add(p["version"])
    for c, vs in sorted(by_check.items()):
        lo, hi = min(vs), max(vs)
        span = ("pre-wrapper" if lo == 0 else f"v{lo}") + ("" if lo == hi else f"–v{hi}")
        n = sum(1 for p in pages if c in p["fails"])
        print(f"fail [{c}]: {n} page(s), {span}")
    print(f"pages processed: {len(pages)}")


if __name__ == "__main__":
    main()
