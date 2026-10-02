#!/usr/bin/env python3
"""Wrap ad-hoc report content in the document envelope (route B of the
local-first artifact rule). Logic lives here; wrap-report.sh is the entry.

Reads page content on stdin — exactly what `artifact-design` teaches you to
write, and exactly what the Artifact tool expects at publish time: styles and
markup, no doctype/html/head/body of your own. Emits a complete document on
stdout by calling the same `_shell.document()` the dash renderers use, or writes it to
`--out <file>` and verifies the artifact contract on that file before returning.

A leading <style>...</style> block in the input is lifted into <head> so the
page's own rules sit after the minimal reset and win; everything else stays in
<body>.
"""
import argparse
import datetime
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import md_body  # noqa: E402
from _shell import document, esc  # noqa: E402

LEADING_STYLE = re.compile(r"\A\s*((?:<style\b[^>]*>.*?</style>\s*)+)", re.S | re.I)
# `- language: es` in the project style profile. A FIELD, not prose: the prose
# form sat in the template for weeks and nothing could read it.
LANG_FIELD = re.compile(r"^\s*[-*]?\s*language\s*:\s*([A-Za-z][A-Za-z0-9-]*)", re.M)
# The `## Language` section's body, up to the next `#`/`##` heading: where the
# field is declared (profile_language).
LANG_SECTION = re.compile(r"^##[ \t]+Language[ \t]*$(.*?)(?=^#{1,2}[ \t]|\Z)",
                          re.M | re.S | re.I)
# A profile that NAMES a language in prose but declares no `language:` field is
# the one failure mode the BL-279 page check cannot see: the wrapper falls to
# "en", the body is written in English to match, and page and <html lang> agree,
# so the check passes on a consistently-wrong artifact. Measured 2026-09-07:
# work_hours_ws said "Default for this project's artifacts: **Spanish** (neutral
# LATAM)" in prose and had shipped English artifacts silently. A default nobody
# chose must announce itself.
PROSE_LANG = re.compile(r"(?i)\b(espa[nñ]ol|spanish|neutral\s+latam|fran[cç]ais|french|"
                        r"portugu[eê]s|portuguese|deutsch|german|italiano|italian)\b")
# `- Favicon emoji: `X`` in the style profile, backticks optional. Same shape as
# LANG_FIELD and for the same reason: a value the wrapper can act on, not prose.
FAVICON_FIELD = re.compile(r"^\s*[-*]?\s*favicon(?:\s+emoji)?\s*:\s*`?([^`\n]{1,8}?)`?\s*$",
                           re.M | re.I)
# The project's CSS delta over the kit: the first ```css fence inside a `## Delta`
# SECTION. Scoped by section, not by "the first css fence in the file" and not by
# a marker on the fence, because both of those are satisfied by the profile
# DOCUMENTING the feature. The first version took the first fence; the first
# profile written against it carried an example, which was injected as the
# project's real palette and turned the next artifact's accents magenta. Marking
# the fence only moved the collision, since the example has to show the marker.
# A section is the one form a document can explain without becoming.
DELTA_SECTION = re.compile(r"^(#{2,6})[ \t]*Delta\b[^\n]*\n(.*?)(?=^\1[ \t]|\Z)",
                           re.M | re.S | re.I)
DELTA_CSS = re.compile(r"^```css[ \t]*\n(.*?)^```", re.M | re.S)
# The one sequence that ends a <style> element, per the HTML spec. A delta
# carrying it is markup, not CSS: everything after it is parsed as HTML, so a
# profile could put a <script> into every artifact the project generates. The
# profile is a file in the repo, which a clone or an edit can carry, and the
# kit's whole value is that it runs in every project — which is also the blast
# radius. Matched narrowly rather than rejecting every `<`, so CSS that
# legitimately contains one (`content: "<"`) still works.
STYLE_BREAKOUT = re.compile(r"</\s*style", re.I)
OFFER_MARKER = ".aidex-artifact-style-offered"

# .../scripts/dash/wrap_report.py -> .../assets/artifact-kit
KIT_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                       os.pardir, os.pardir, "assets", "artifact-kit"))


def split_head_style(content):
    """Return (head_extra, body). Only a style block at the very top is lifted —
    a <style> further down is the author's deliberate placement, left alone."""
    m = LEADING_STYLE.match(content)
    if not m:
        return "", content.strip()
    return m.group(1).strip(), content[m.end():].strip()


# .../skills/artifact/scripts/dash/wrap_report.py -> .../skills
_SKILLS_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                           os.pardir, os.pardir, os.pardir))
LIB_SH = os.path.join(_SKILLS_DIR, "conventions", "scripts", "_lib.sh")


def find_context_dir(start):
    """`<project-root>/.context` for the project `start` belongs to, or None.

    Delegates to `_lib.sh`'s `find_project_root`, the shared resolver 33 scripts
    already use. This used to be a private Python reimplementation of it, and was
    missing the linked-worktree hop — so route B (this script) and route A
    (render.sh, which sources _lib.sh) resolved DIFFERENT roots for the same
    project. render.sh:15-19 records that its own copy was deleted for exactly
    these fixes; the no-private-copies guard could not see this one because it
    greps for a bash function definition and this was a Python function under
    another name.

    A linked worktree is a SIBLING of the project, never a descendant, so an
    upward walk cannot reach the main tree's `.context/` — which is gitignored and
    therefore absent from the worktree. The consequences were a page written with
    the wrong `lang`, and a one-time offer that never fired and never recorded
    itself: the "rule with no memory" half of BL-168 that the marker exists to fix.

    `find_project_root` resolves from the working directory, so `start` is passed
    as the cwd of the call rather than as an argument.
    """
    if not os.path.isdir(start) or not os.path.isfile(LIB_SH):
        return None
    try:
        r = subprocess.run(
            ["bash", "-c", '. "$1" >/dev/null 2>&1; find_project_root', "_", LIB_SH],
            cwd=start, capture_output=True, text=True)
    except OSError:
        return None
    root = r.stdout.strip()
    if r.returncode != 0 or not root:
        return None
    return os.path.join(root, ".context")


def _kit(name):
    """One kit file, or None when the kit is missing.

    Missing is a real state — an install that predates the kit, or a checkout of
    the scripts alone — and it degrades to the pre-kit behaviour (the page keeps
    whatever styles it carries itself) rather than failing the wrap.
    """
    path = os.path.join(KIT_DIR, name)
    try:
        return open(path, encoding="utf-8").read()
    except OSError:
        return None


def kit_head():
    """The kit's head half: a version stamp and the two stylesheets, INJECTED.

    Never linked. A local artifact is one file with no network, and a published
    one is served under a CSP that blocks every external host; a <link> would
    strip the page of its styles in both places.

    Order matters. `document()` emits the reset first, this second, and the
    caller appends the project delta and then the page's own <style> — so a
    project overriding a token beats the kit, and a page overriding a rule beats
    its project.
    """
    tokens, components = _kit("tokens.css"), _kit("components.css")
    if tokens is None or components is None:
        return ""
    version = (_kit("VERSION") or "").strip() or "unknown"
    return (f'<meta name="artifact-kit" content="{esc(version)}">\n'
            f"<style>\n{tokens}</style>\n"
            f"<style>\n{components}</style>")


CONSULT_ROUND = re.compile(
    r'<meta\b[^>]*\bname\s*=\s*["\']?consult-round["\']?[^>]*'
    r'\bcontent\s*=\s*(?:"(\d+)"|\'(\d+)\'|(\d+))', re.I | re.S)


def _round_of(path):
    """The `consult-round` a page on disk carries, or 0 when it carries none."""
    try:
        m = CONSULT_ROUND.search(open(path, encoding="utf-8",
                                      errors="replace").read())
    except OSError:
        return 0
    return int(next(g for g in m.groups() if g is not None)) if m else 0


def _baseline_path(outfile):
    """The `.aidex-artifact-prev/` copy of `--out`: the last version that PASSED."""
    out = os.path.abspath(outfile)
    return os.path.join(os.path.dirname(out), ".aidex-artifact-prev",
                        os.path.basename(out))


def _answered_path(outfile):
    """The snapshot `save_reply.py` takes of the page the reader answered."""
    stem = os.path.splitext(os.path.basename(outfile))[0]
    return os.path.join(os.path.dirname(os.path.abspath(outfile)),
                        ".aidex-artifact-prev", stem + ".answered.html")


def _current_round(outfile):
    base = _baseline_path(outfile)
    ref = base if os.path.isfile(base) else os.path.abspath(outfile)
    return (_round_of(ref) or 1) if os.path.isfile(ref) else 0


def round_answered(outfile):
    """True when the page's CURRENT round has a saved reply (BL-507).

    The answered snapshot is a copy of the page as the reader answered it, so it
    carries the round it answered; the baseline carries the round the reader has.
    Snapshot round >= baseline round means that round was answered."""
    base = _baseline_path(outfile)
    ref = base if os.path.isfile(base) else os.path.abspath(outfile)
    answered = _answered_path(outfile)
    if not os.path.isfile(answered) or not os.path.isfile(ref):
        return False
    return (_round_of(answered) or 1) >= (_round_of(ref) or 1)


def next_round(outfile, surface=True):
    """The round number the page about to be written is, or 0 when it is not a
    round of anything (no `--out`). See `round_meta` for why the BASELINE, and
    not the file on disk, is what it counts from.

    BL-507: on a page with a consult surface this is the READER's round, not the
    wrap count. It advances only once save-reply.sh has recorded an answer to
    the current round; a re-wrap of an unanswered round keeps its number. A page
    with no consult surface has no reader rounds and keeps counting wraps."""
    if not outfile:
        return 0
    out = os.path.abspath(outfile)
    baseline = _baseline_path(out)
    if os.path.isfile(baseline):
        prev = _round_of(baseline) or 1
    elif os.path.isfile(out):
        prev = _round_of(out) or 1
    else:
        prev = 0
    if surface and prev and not round_answered(out):
        return prev
    return prev + 1


def round_meta(outfile, surface=True):
    """`<meta name="consult-round">` for the page about to be written.

    What it is for: the composer keeps typed answers in localStorage and used to
    restore them into every later regeneration, so notes the session had already
    read and acted on were handed back to the reader round after round. The
    marker is how the page tells "the reader reloaded me" from "this is a new
    round"; the composer then drops only what was already SENT (see composer.js
    § the ROUND).

    Derived from the BASELINE, never from the file on disk. A wrap that fails the
    contract does NOT advance the baseline, so counting from disk would increment
    twice across a failed wrap and a fixed one — blanking sent-answer state on a
    round the reader never saw. (The rollback makes disk agree again in the common
    case; it does not restore the invariant, because a page deleted by hand and
    re-wrapped would still count from nothing.)
    The on-disk file is only the fallback for a page written before baselines
    existed.

    A wrap to stdout has no path and therefore no round. That is correct rather
    than a gap: without `--out` there is no thread to be a round of, and a page
    with no marker keeps the pre-round behaviour exactly.
    """
    r = next_round(outfile, surface)
    return f'<meta name="consult-round" content="{r}">' if r else ""


ITEM_TAG = re.compile(r'<[a-zA-Z][\w:-]*\b[^>]*\bdata-id\s*=[^>]*>', re.I)
ATTR_ID = re.compile(r'\bdata-id\s*=\s*(?:"([^"]*)"|\'([^\']*)\'|([^\s>]+))', re.I)
# `data-decided` and NOT `data-decided-round`: `\b` after "decided" is satisfied by
# the hyphen, so the plain pattern reads the stamp as the mark it stamps.
ATTR_DECIDED = re.compile(
    r'\bdata-decided\b(?!-)(?:\s*=\s*(?:"([^"]*)"|\'([^\']*)\'|([^\s>]+)))?', re.I)
ATTR_DECIDED_ROUND = re.compile(
    r'\bdata-decided-round\s*=\s*(?:"(\d+)"|\'(\d+)\'|(\d+))', re.I)
# The attribute however it is spelled, valid or not. The digits-only pattern above
# decides whether to KEEP a hand-written stamp; this one is how the attribute is
# found for replacement, so `data-decided-round="two"` is corrected in place
# instead of being invisible and answered with a second copy of the attribute.
ANY_DECIDED_ROUND = re.compile(
    r'\s*\bdata-decided-round\b(?:\s*=\s*(?:"[^"]*"|\'[^\']*\'|[^\s>]+))?', re.I)


def _attr(rx, tag):
    """The attribute's value, `""` for a bare attribute, None when it is absent.
    Bare and absent are different states here: `data-decided` with no value is a
    decision whose verdict line is derived from the ticked options."""
    m = rx.search(tag)
    if not m:
        return None
    return next((g for g in m.groups() if g is not None), "")


def decided_rounds_of(path):
    """`{data-id: (verdict, round or None)}` for the DECIDED items of a page on
    disk — `None` when the item carries no usable stamp, which is every page
    whose last passing render predates BL-421. Decided-without-a-stamp and
    not-decided-at-all are different states and the caller acts differently on
    them, so the absent stamp is carried, not dropped. A stamp whose value is not
    digits is no stamp."""
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return {}
    out = {}
    for tag in ITEM_TAG.findall(text):
        ident, verdict = _attr(ATTR_ID, tag), _attr(ATTR_DECIDED, tag)
        stamp = _attr(ATTR_DECIDED_ROUND, tag)
        if ident and verdict is not None:
            out[ident] = (verdict, int(stamp) if stamp else None)
    return out


def stamp_decided_rounds(body, outfile, this_round):
    """Write `data-decided-round` onto every decided item (BL-421).

    The page stores its round once, in a meta, and the verdict TEXT on
    `data-decided` — so "how many rounds did this consultation take to decide
    everything" was not derivable from the page, which is what the artifacts
    facet promised its reader. The round an item was decided in is a property of
    the moment it was decided, so it is stamped here, where the round is known.

    The author's source (the `.body` sidecar) carries no stamp and must not have
    to: it is re-wrapped every round, so a stamp derived from the source alone
    would be the CURRENT round every time and an item decided in round 1 would
    read as decided in round 5. The previous PASSING render is the carrier —
    an item decided there, with the same verdict, keeps the round it got there;
    anything else (newly decided, or re-decided with a different verdict) takes
    this round. An author who spells a VALID `data-decided-round` by hand is left
    alone.

    The migration case is the one that must stay silent: a baseline written before
    this existed has decided items and no stamp on any of them, and those items
    were decided in some round nobody recorded. They stay UNSTAMPED — the reader
    reports them `unknown` — because stamping them with the round of the wrap that
    happens to migrate the page is a confident wrong answer, and one that would
    then be carried forward as fact by every later round.
    """
    if not outfile or not this_round:
        return body
    baseline = _baseline_path(outfile)
    prev = decided_rounds_of(baseline if os.path.isfile(baseline)
                             else os.path.abspath(outfile))

    def one(m):
        tag = m.group(0)
        verdict = _attr(ATTR_DECIDED, tag)
        # An undecided item is never stamped, and a stamp already there is the
        # author's markup: this writes the round of a decision, it does not tidy.
        if verdict is None:
            return tag
        if ATTR_DECIDED_ROUND.search(tag):
            return tag
        was = prev.get(_attr(ATTR_ID, tag) or "")
        # Compared in the plain form `decide` compares in (BL-545): `**x**` is
        # the verdict `x` re-spelled, not a new decision.
        carried = was is not None and (md_body.PLAIN.sub("", was[0]).strip()
                                       == md_body.PLAIN.sub("", verdict).strip())
        rnd = was[1] if carried else this_round
        present = ANY_DECIDED_ROUND.search(tag)      # an invalid hand stamp
        if rnd is None:
            return ANY_DECIDED_ROUND.sub("", tag, count=1) if present else tag
        if present:
            return ANY_DECIDED_ROUND.sub(
                lambda _m: f' data-decided-round="{rnd}"', tag, count=1)
        inner = tag[1:-1].rstrip()
        selfclose = inner.endswith("/")
        if selfclose:
            inner = inner[:-1].rstrip()
        return f'<{inner} data-decided-round="{rnd}"' + ("/>" if selfclose else ">")

    return ITEM_TAG.sub(one, body)


def kit_script():
    """The composer, for the END of <body>.

    Not <head>: it queries `#raillist` and `.consult-item` on load, and from the
    head those are all null, so the rail never builds and every page silently
    loses its index.
    """
    composer = _kit("composer.js")
    return "" if composer is None else f"<script>\n{composer}</script>"


def profile_delta(ctx):
    """The project's CSS delta over the kit, as a <style> block, or ""."""
    text = _profile_text(ctx)
    if not text:
        return ""
    section = DELTA_SECTION.search(text)
    if not section:
        return ""
    m = DELTA_CSS.search(section.group(2))
    if not m:
        return ""
    css = m.group(1)
    if STYLE_BREAKOUT.search(css):
        # Refused WHOLE and out loud. Escaping the sequence would inject
        # something the author did not write, and dropping it quietly would make
        # a refused delta look like a project that simply has none.
        print("ERROR: the project's CSS delta closes the <style> element, so it is "
              "markup rather than CSS. It has NOT been injected. Remove the "
              "</style> from the `## Delta` section of .context/artifact-style.md.",
              file=sys.stderr)
        return ""
    return f"<style>\n{css}</style>"


def profile_favicon(ctx):
    """The project's favicon emoji, or None.

    Precedence mirrors `language:` — an explicit --favicon wins, this fills in.
    """
    text = _profile_text(ctx)
    if not text:
        return None
    m = FAVICON_FIELD.search(text)
    if not m:
        return None
    value = m.group(1).strip()
    # The template ships a `{{one emoji, ...}}` placeholder; a project that never
    # filled it in has no favicon, not a favicon spelled with braces.
    return None if not value or value.startswith("{{") else value


def _profile_text(ctx):
    """artifact-style.md as text, or None. Shared by every profile reader."""
    if not ctx:
        return None
    path = os.path.join(ctx, "artifact-style.md")
    if not os.path.isfile(path):
        return None
    # `isfile` only stats; it does not imply readable, and `errors="replace"`
    # covers decode failures but not OSError. A mode-000 profile used to abort the
    # whole wrap with a traceback and write no artifact at all. The profile is an
    # optimisation, not a contract: say so and fall back to the defaults.
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError as e:
        print(f"NOTE: could not read {path} ({e}); falling back to the default "
              f"artifact style.", file=sys.stderr)
        return None


def _takes_english(outfile):
    """human-verification.* is the one page English by D-04 whatever the profile
    says (contract_defects exempts it from lang-follows-profile too). A close-out
    record under worklists/_archive/ follows the profile (BL-382, BL-482)."""
    return bool(outfile) and os.path.basename(outfile).startswith("human-verification.")


def profile_language(ctx):
    """The project's configured artifact language, or None.

    Scope is ARTIFACTS. `.context/` stays English (D-04) whatever this says, and
    `communications/` keep the language they arrived in — this field only decides
    what a report a human reads is written in.

    The declaration is the field inside `## Language`, wherever that section
    sits (last in some profiles, near the top in others): a line elsewhere that
    happens to read `- language: xx` (a worked example, a note about another
    surface) is not it. With no such section, or none in it, the first field in
    the file is. conventions/scripts/validate.py carries a copy of this reader.
    """
    text = _profile_text(ctx)
    if not text:
        return None
    sec = LANG_SECTION.search(text)
    m = (sec and LANG_FIELD.search(sec.group(1))) or LANG_FIELD.search(text)
    return m.group(1) if m else None


def style_profile_offer(ctx):
    """Text for the one-time style-profile offer, or None when it is not due.

    The offer is due exactly once per project. Both halves of that were broken:
    it never fired on the artifact that prompted BL-168, while a usage-retro
    measured it firing 14 times across 7 projects with 6 ignored. A rule that is
    simultaneously missed and nagging is a rule with no memory; the marker is
    that memory. The PROFILE is still never auto-created (e87bbd3) — only the
    record that the offer was made is.
    """
    if not ctx or os.path.isfile(os.path.join(ctx, "artifact-style.md")):
        return None
    marker = os.path.join(ctx, OFFER_MARKER)
    if os.path.exists(marker):
        return None
    try:
        with open(marker, "w", encoding="utf-8") as fh:
            fh.write("The artifact style profile was offered once, when this project's "
                     "first artifact was wrapped. Delete this file to offer it again.\n")
    except OSError:
        return None  # read-only tree: skip the offer rather than nag on every run
    return ("NOTE: this project has no .context/artifact-style.md, so this artifact's "
            "palette, fonts, favicon and language are being invented here and lost. "
            "Offer the profile to the reader ONCE, now — seed it from "
            "artifact/assets/templates/artifact-style.md.template, prefilled with the "
            "choices just made. Do not create it unasked. This offer is now recorded in "
            f"{marker} and will not fire again.")


def _warn_prose_only_language(ctx):
    """Say so when a profile declares its language in prose and not as a field.

    Silent is the defect. `lang` resolves to "en", the author writes English to
    match, and every downstream check agrees with itself -- so nothing reports
    that the project asked for another language and did not get it.
    """
    text = _profile_text(ctx)
    if not text:
        # No readable profile. style_profile_offer() owns the FIRST artifact of a
        # project: it fires once, names language among what is being invented, and
        # writes the marker so it cannot become the nag BL-168 removed. What it
        # does NOT own is every artifact after that one -- and BL-322 measured what
        # was left there: nothing, at any layer, while each artifact went out
        # lang="en". check-artifact's lang gate cannot see it either, because an
        # English body under lang="en" is self-consistent; absence is only visible
        # from here. The offer is not repeated; the FACT is stated instead.
        #
        # The marker is what tells the two apart, and reading it here is sound
        # because this runs BEFORE style_profile_offer() creates it: present means
        # the offer was made on an earlier run, not that it is about to fire now.
        if ctx and os.path.exists(os.path.join(ctx, OFFER_MARKER)):
            print(f'NOTE: no language is declared for {ctx} -- no artifact-style.md '
                  f'`language:` field and no --lang -- so this artifact is being '
                  f'wrapped as lang="en". Add a `- language: <code>` line to '
                  f'{ctx}/artifact-style.md, or pass --lang.', file=sys.stderr)
        return
    m = PROSE_LANG.search(text)
    if not m:
        return          # profile present and silent on language: "en" is the real answer
    print(f"NOTE: {ctx}/artifact-style.md mentions {m.group(1)!r} in prose but declares no "
          f"`language:` field, so this artifact is being wrapped as lang=\"en\". Add a "
          f"`- language: <code>` line to the profile, or pass --lang.", file=sys.stderr)



def rail_aside(lang):
    return ('<aside class="rail">\n  <p class="railhead">%s</p>\n'
            '  <nav class="raillist" id="raillist"></nav>\n</aside>'
            % esc(md_body.railhead(lang)))


def inject_rail(body, lang="en"):
    """Add the skeleton's rail aside after </main> when the body has none.

    md_body emits it for markdown; the .html body path relied on the author
    copying it from skeleton.html, and two delegated pages shipped without it
    (D4, 2026-09-13). The aside is inert without the composer, which every
    wrapped page carries, so injecting it is never wrong on a kit page.
    """
    if re.search(r'id=["\']raillist["\']', body) or "</main>" not in body:
        return body
    return body.replace("</main>", "</main>\n" + rail_aside(lang), 1)


# Where each md_body.CHROME string sits on a kit page: the opening tag of a text
# label, or the textarea whose placeholder it is. Mirrors composer.js CHROME.
_LABEL = r'<[a-z]+\b[^>]*\bclass="fieldlabel"[^>]*>'
CHROME_SITES = (
    ("copy", "text", r'<button\b[^>]*\bid="consult-copy(?:-end)?"[^>]*>'),
    ("contents", "text", r'<p class="railhead">'),
    ("notes", "text", _LABEL), ("choice", "text", _LABEL),
    ("value", "text", _LABEL), ("general", "text", _LABEL),
    ("notesPh", "placeholder", None), ("listPh", "placeholder", None),
    ("valuePh", "placeholder", None), ("generalPh", "placeholder", None),
)


def _kit_value(v):
    """A kit string as the source may spell it: the ellipsis raw or as an entity."""
    return re.escape(v).replace("…", "(?:…|&hellip;|&#8230;)")


def _chrome_sub(body, target, sources, kinds=("text", "placeholder")):
    """Every CHROME site whose text is the `sources` languages' kit string,
    rewritten as the `target` language's."""
    for key, kind, opening in CHROME_SITES:
        if kind not in kinds:
            continue
        values = "|".join(_kit_value(md_body.CHROME[key][l]) for l in sources
                          if l in md_body.CHROME[key])
        if not values:
            continue
        if kind == "text":
            pat = r"(%s)(\s*(?:%s)\s*)(</)" % (opening, values)
        else:
            pat = r'(<textarea\b[^>]*?\bplaceholder=")(%s)(")' % values
        body = re.sub(pat, lambda m: m.group(1) + esc(md_body.chrome(key, target))
                      + m.group(3), body)
    return body


def localize_chrome(body, lang):
    """The kit's English chrome defaults (md_body.CHROME), as skeleton.html and
    the consultation template ship them, rewritten in the page's language. The
    HTML route copies English defaults; a reader with no JS (a static snapshot)
    saw them on a Spanish page (LOOP-006 ui-string-language). Only the exact
    English defaults are translated, as composer.js:306-316 does; an author's
    own label, in any language, stays."""
    return _chrome_sub(body, lang, ["en"])


def chrome_to_english(body):
    """The inverse on the text sites, for comparing questions: a translated kit
    label put back into English, as composer.js questionHash does before it
    hashes (:868-872)."""
    others = sorted({l for t in md_body.CHROME.values() for l in t} - {"en"})
    return _chrome_sub(body, "en", others, kinds=("text",))


# --- when this page was built (BL-439, audit finding USAGE-29) ---------------
# The reader asked eight times across two retro windows whether the tab he had
# open was the page that had just been written. Naming the absolute path in the
# reply answers WHICH FILE and never WHICH VERSION, and a page that is re-wrapped
# in place is byte-different and pixel-identical until it is reloaded. So the
# page says when it was built, and the wrap prints the same line, and the two are
# compared by eye.
#
# Written HERE and not in composer.js on purpose: a local page opened through a
# viewer that shows it as a static snapshot runs no script, and that is exactly
# the reader who cannot tell. Local time of the machine that wrapped, to the
# minute — a stamp nobody can read against their own clock answers nothing.
BUILT_FORMAT = "%Y-%m-%d %H:%M"
# Two words per language, in the page's language, like every other piece of kit
# chrome. composer.js's STRINGS table is the other half of this and cannot be
# reached from here: it runs in the browser, and this line exists precisely for
# the page that never runs it.
BUILT_LABELS = {"en": ("Built", "round"), "es": ("Generado", "ronda")}
BUILT_P = re.compile(r'[ \t]*<p class="railbuilt"[^>]*>.*?</p>\n?', re.I | re.S)
# The rail is an ELEMENT, and the stamp goes inside that element. Anchoring on
# the first `id="raillist"` string in the document put it inside an
# `<aside class="note">` of the page's own, on a page that quoted the kit's
# markup in a <code> (nothing escapes the quotes there) — with the count still
# reading exactly one, which is what a count-based check cannot see.
ASIDE_OPEN = re.compile(r"<aside\b[^>]*>", re.I)
CLASS_ATTR = re.compile(r'\bclass\s*=\s*(?:"([^"]*)"|\'([^\']*)\'|([^\s>]+))', re.I)
ASIDE_TAG = re.compile(r"</?aside\b", re.I)
# Closed on the right: `id="raillist-old"` is another element's id and must not
# answer for a rail the page does not have.
RAILLIST_ID = re.compile(r'id=["\']?raillist(?=["\'\s>])', re.I)
# What makes a page a consultation is that it carries questions. `data-id` alone
# does not: a consultation BLOCK carries one too, and so may an author's own
# markup on a page that asks nothing — the round belongs on the pages that have
# rounds.
CONSULT_ITEM = re.compile(r'class=["\'][^"\']*consult-item', re.I)


def built_text(lang, rnd, when=None):
    """The one line the page shows: `Built 2026-09-21 08:24 · round 3`.

    `rnd` is falsy on anything that is not a consultation round, and the clause
    is then absent rather than empty — a read has no round, and a `· round 1` on
    every report would make the number mean "wrapped once" instead.
    """
    label, round_word = BUILT_LABELS.get((lang or "en")[:2].lower(),
                                         BUILT_LABELS["en"])
    stamp = (when or datetime.datetime.now()).strftime(BUILT_FORMAT)
    return f"{label} {stamp}" + (f" · {round_word} {rnd}" if rnd else "")


def _rail_aside(body):
    """The `<aside>` whose class list carries the token `rail`, or None.

    By class TOKEN, not by a substring: `raillist` contains `rail` and a
    `rail-legacy` is not this element either.
    """
    for m in ASIDE_OPEN.finditer(body):
        cm = CLASS_ATTR.search(m.group(0))
        if not cm:
            continue
        classes = next(g for g in cm.groups() if g is not None)
        if "rail" in classes.split():
            return m
    return None


def _closing_aside(body, start):
    """Offset of the `</aside>` that closes the aside opened at `start`.

    Counted, not found: the rail may legitimately contain an `<aside>` of its
    own, and taking the first closing tag would land the stamp inside it.
    """
    depth = 0
    for tok in ASIDE_TAG.finditer(body, start):
        depth += 1 if tok.group(0).lower() == "<aside" else -1
        if depth == 0:
            return tok.start()
    return -1


def insert_built_line(body, text):
    """Put the built line at the end of the rail, replacing any line already
    there.

    Replacing and not appending is the whole property: a body handed back from
    the wrapped page instead of from the `.body` sidecar would otherwise grow a
    second stamp per round, and two stamps is exactly what `double-wrap` reads
    as a page carrying two kits.

    A body with no rail keeps the meta and loses the visible line. That is not a
    silent hole: `check_artifact.py`'s `rail` check already fails a page with no
    `#raillist`, so the only pages that reach it are wraps to stdout, which the
    contract never verifies either.
    """
    body = BUILT_P.sub("", body)
    rail = _rail_aside(body)
    end = _closing_aside(body, rail.start()) if rail else -1
    if end < 0:
        # No rail aside: a hand-written index inside some other element. The old
        # anchor is kept as the fallback rather than dropping the line — it is
        # wrong only when a page BOTH quotes the markup and has no rail, and
        # then there is nothing right to do with it.
        m = RAILLIST_ID.search(body)
        end = body.find("</aside>", m.end()) if m else -1
    if end < 0:
        return body
    return f'{body[:end]}  <p class="railbuilt">{esc(text)}</p>\n{body[end:]}'


# --- which QUESTIONS changed since the previous render (USAGE-21) ------------
# Since kit v6 the composer fingerprints each item's question body and
# `restore()` skips an answer whose fingerprint moved: that item reads blank on
# the new round and the page's banner tells the READER how many were dropped.
# Nothing told the WRITER WHICH questions he had just rephrased, so a round could
# quietly cost an answer that was typed and never sent — and the writer is the
# one who can still say so in the reply.
#
# "Changed" has to mean what composer.js means by it, and Python cannot run
# composer.js, so an item is normalised here the way `questionHash` normalises
# its clone: the controls the kit INJECTS are dropped, every `[contenteditable]`
# subtree is emptied (its text is the reader's own typing, not the question), and
# what is left is taken the way `textContent` takes it — tags vanish, they do
# not become spaces — with whitespace collapsed. Two steps of that function
# are deliberately not mirrored, and none of them can invent a difference this
# does not have:
#   - the FNV hash: the normalised text is compared directly, so there is no
#     collision to worry about either;
#   - `<option>` text is kept, exactly as the composer keeps it.
# Its `.fieldlabel` re-translation IS mirrored (`chrome_to_english`): the wrap
# writes kit labels in the page's language since LOOP-006, and without it every
# re-wrap of an older page would report every question as changed.
# A class is matched as a whole token and `contenteditable` as an attribute
# NAME: `\b` is satisfied by a hyphen, the trap `ATTR_DECIDED` records above.
CONSULT_ITEM_OPEN = re.compile(
    r'<([a-zA-Z][\w:-]*)\b[^>]*\bclass\s*=\s*["\'](?:[^"\']*\s)?'
    r'consult-item(?=[\s"\'])[^>]*>',
    re.I | re.S)
# What `questionHash` removes from the clone before hashing. A render saved out
# of a browser carries these; the item they sit in is the same question.
QUESTION_DROP = re.compile(
    r'<([a-zA-Z][\w:-]*)\b(?:[^>"\']|"[^"]*"|\'[^\']*\')*?'
    r'(?:\scontenteditable(?=[\s=>/])'
    r'|\sclass\s*=\s*["\'](?:[^"\']*\s)?'
    r'(?:kit-tag|consult-clear|kit-other|kit-notnow|kit-ask|kit-provisional)'
    r'(?=[\s"\']))'
    r'[^>]*>', re.I | re.S)
VOID_ELEMENTS = {"area", "base", "br", "col", "embed", "hr", "img", "input",
                 "link", "meta", "param", "source", "track", "wbr"}


def question_texts(text):
    """`{data-id: the item's QUESTION}` for every `.consult-item` of a render.

    `.consult-item` and not every `data-id`, because that is the composer's own
    `items`: a block (`.consult-group`) carries an id too and CONTAINS its
    questions, so judging it as well would name the block every time one of its
    items was rephrased.

    `_subtree` and `strip_script_style` come from `check_artifact` rather than
    from a copy here — a private second implementation of a shared walk is
    exactly what `find_context_dir` above records the cost of.
    """
    import check_artifact as ca

    def question_of(body):
        body = chrome_to_english(re.sub(r"<!--.*?-->", "", body, flags=re.S))
        kept, pos = [], 0
        for m in QUESTION_DROP.finditer(body):
            if m.start() < pos:
                continue                 # already inside a dropped subtree
            if (m.group(1).lower() in VOID_ELEMENTS
                    or m.group(0).rstrip().rstrip(">").endswith("/")):
                continue                 # no subtree, and no text of its own
            sub = ca._subtree(body, m.group(1), m.end())
            kept.append(body[pos:m.start()])
            pos = m.end() + len(sub)
            close = re.match(r"</" + re.escape(m.group(1)) + r"\s*>",
                             body[pos:], re.I)
            if close:
                pos += close.end()
        kept.append(body[pos:])
        plain = html.unescape(re.sub(r"<[^>]+>", "", "".join(kept)))
        return re.sub(r"\s+", " ", plain).strip()

    out = {}
    text = ca.strip_script_style(text)
    for m in CONSULT_ITEM_OPEN.finditer(text):
        ident = _attr(ATTR_ID, m.group(0))
        if ident:
            out[ident] = question_of(ca._subtree(text, m.group(1), m.end()))
    return out


def changed_questions(prev_text, new_text):
    """The ids whose question differs between two renders, in the NEW render's
    order.

    An id on one side only is not one of them. An added question was never
    answered, and a removed one is no longer on the page for an answer to
    restore into — reporting either would make the note fire on every round that
    opens or closes a claim, which is every round.
    """
    old = question_texts(prev_text)
    return [i for i, q in question_texts(new_text).items()
            if i in old and old[i] != q]


def lock_path(outfile):
    """The build lock for `outfile`, beside its contract baseline.

    One file, named after the page, so the state is per PAGE. The alternative
    considered and rejected was a transcript-scoped guard ("refuse an open while
    any agent is pending"): replayed over every main session since 2026-09-14 it
    blocked 18 of 26 real opens, nearly all of them pages no pending agent was
    touching.
    """
    out = os.path.abspath(outfile)
    return os.path.join(os.path.dirname(out), ".aidex-artifact-prev",
                        os.path.basename(out) + ".building")


def held_round(outfile):
    """The round a build in progress DISPLAYS, or 0 when no build holds it.

    A delegated build wraps its page several times and the reader sees none of
    the intermediate states — `artifact-open-once.sh` refuses to open a locked
    page — yet every one of those wraps passes, advances the baseline and
    therefore the round. Three wraps handed the reader `· round 3` for a page
    he had never seen, on the one line whose whole job is to be trusted.

    So the lock carries the round the build STARTED at, and every wrap of that
    build shows it. Since BL-507 `consult-round` is the reader's round and no
    longer counts wraps on a consult page, so this hold is belt-and-braces there;
    it still matters for a page that has no reply to wait for.

    A lock written before this existed carries no number: fall back to the
    wrap's own round rather than inventing one.
    """
    if not outfile:
        return 0
    try:
        with open(lock_path(outfile), encoding="utf-8") as fh:
            for line in fh:
                if line.strip().isdigit():
                    return int(line.strip())
    except OSError:
        return 0
    return 0


def end_build(argv):
    """`--done --out <page>`: the build is over. Removes the lock, wraps nothing.

    Deliberately NOT a flag on the last wrap. A passing wrap is not the end of a
    build — the incident this exists for is an INTERMEDIATE wrap that passed the
    contract and was opened as final — so no property of a wrap can stand in for
    completion. The agent has to say it, once, as its own step.
    """
    p = argparse.ArgumentParser(prog="wrap-report.sh --done",
                                description="End a build: remove the page build lock")
    p.add_argument("--done", action="store_true", required=True)
    p.add_argument("--out", dest="outfile", required=True,
                   help="the page whose build is finished")
    args = p.parse_args(argv)
    lock = lock_path(args.outfile)
    try:
        os.unlink(lock)
    except OSError:
        # Idempotent on purpose: a build that never locked, a second --done, a
        # lock already swept. Every build must be endable the same way, so this
        # is a note and never an error.
        print(f"NOTE: no build lock at {lock} — nothing to clear.", file=sys.stderr)
        return 0
    print(f"build lock cleared: {lock}", file=sys.stderr)
    return 0


def main():
    p = argparse.ArgumentParser(description="Wrap report content in the document envelope")
    p.add_argument("--title", required=True, help="document title (browser tab)")
    p.add_argument("--lang", default=None,
                   help="BCP-47 language of the content. Default: the `language:` field of "
                        "<project>/.context/artifact-style.md, else en")
    p.add_argument("--favicon", default="", help="one or two emoji for the tab icon")
    p.add_argument("--in", dest="infile", help="read content from this file instead of stdin")
    p.add_argument("--out", dest="outfile",
                   help="write the document here and run check-artifact.sh on it. Prefer "
                        "this over a shell redirect: the contract check is the step a run "
                        "drops first, and it cannot run against a pipe (BL-126)")
    p.add_argument("--building", action="store_true",
                   help="this wrap is one step of a build that is still running: keep a "
                        "lock beside the page so nobody opens it as final. End the build "
                        "with --done --out <page>. For a DELEGATED build; a session "
                        "wrapping its own page and opening it does not pass this")
    p.add_argument("--new-round", action="store_true",
                   help="assert this wrap opens a new reader round: refused, naming "
                        "save-reply.sh, when the current round has no saved reply")
    p.add_argument("--done", action="store_true",
                   help="with --out and nothing else: the build is finished, remove the "
                        "lock. Wraps nothing")
    args = p.parse_args()

    # A lock lives beside the page, so there is nothing to lock without --out. Wrapping
    # anyway would produce the one state the flag exists to prevent: output that looks
    # finished while the build runs.
    if args.building and not args.outfile:
        print("ERROR: --building needs --out <page> — the build lock is a file beside "
              "the page, and a wrap to stdout has no page", file=sys.stderr)
        return 2

    content = (open(args.infile, encoding="utf-8").read() if args.infile
               else sys.stdin.read())
    if not content.strip():
        print("ERROR: no content on stdin (nothing to wrap)", file=sys.stderr)
        return 2
    # A `.md` input is the close-out case (BL-345): the run already wrote a
    # durable markdown report and what is missing is the page. Keyed on the
    # EXTENSION rather than a flag because both producers pass a file on disk and
    # neither has anything to say about the conversion — an option here would be
    # a second way to spell the only sensible behaviour. Content on stdin is
    # still page markup: a pipe has no name to read the intent from.
    # `--title` doubles as the fallback h1: `human-verification.md` carries no `# `
    # line, so the page had no on-page heading at all and an empty rail while the
    # caller was already passing the exact title it needed.
    # What the author wrote, before any rendering: this is what the body sidecar
    # keeps, so a markdown report is revised as markdown.
    raw, raw_is_md = content, bool(args.infile and args.infile.lower().endswith(".md"))
    # The style profile is looked up from where the artifact LANDS, not from the
    # cwd: a report is a sibling of its anchor and can be written into a project
    # the run is not standing in.
    ctx = find_context_dir(os.path.dirname(os.path.abspath(args.outfile))
                           if args.outfile else os.getcwd())
    profile_lang = profile_language(ctx)
    lang = args.lang or profile_lang or "en"
    if args.lang is None and profile_lang is None:
        _warn_prose_only_language(ctx)
    elif (args.lang and profile_lang and args.lang != profile_lang
          and not _takes_english(args.outfile)):
        # BL-371: an explicit --lang that contradicts the profile. The check that
        # runs on --out refuses it (lang-follows-profile); this names why first,
        # and says so on stdout wraps too, which that check never sees.
        print(f'NOTE: --lang {args.lang} contradicts {ctx}/artifact-style.md, which '
              f'declares `language: {profile_lang}`. Every page follows the '
              f'profile; only a human-verification.* page takes --lang en by D-04. '
              f'Wrapping as lang="{args.lang}", which check-artifact refuses.',
              file=sys.stderr)

    # After the language is known: the rendered rail is headed in it.
    if raw_is_md:
        content = md_body.render(content, args.title, lang)
    if re.search(r"<!doctype\s+html", content, re.I):
        print("ERROR: content already has a doctype — pass page content only, "
              "not a full document", file=sys.stderr)
        return 2
    head_extra, body = split_head_style(content)
    body = localize_chrome(inject_rail(body, lang), lang)
    # Before the kit is injected: the composer script and the kit CSS both spell
    # `data-decided`, and only the AUTHOR's markup carries items (`data-id`).
    surface = bool(CONSULT_ITEM.search(body))
    this_round = next_round(args.outfile, surface)
    if args.new_round and args.outfile and surface:
        # "This wrap must advance the reader round": refused while the current
        # round is open, i.e. a page exists and has no saved reply for it.
        open_round = _current_round(args.outfile)
        if open_round >= 1 and not round_answered(args.outfile):
            print(f"ERROR: round {open_round} is already open and has no saved reply. "
                  f"If this is a re-wrap of the round you are building, drop --new-round. "
                  f"If the reader has answered round {open_round}, run "
                  f"save-reply.sh {args.outfile} <reply-file> first, then wrap with "
                  f"--new-round.", file=sys.stderr)
            return 1
    body = stamp_decided_rounds(body, args.outfile, this_round)
    # One clock for the meta, the visible line and the line printed at the end,
    # so the three cannot disagree across a minute boundary.
    now = datetime.datetime.now()
    # What the page SHOWS: the round this build started at while a build holds
    # the page, this wrap's round otherwise. Read before the lock is refreshed
    # below — a lock written by this same wrap would answer with this round.
    shown_round = held_round(args.outfile) or this_round
    built = built_text(lang, shown_round if CONSULT_ITEM.search(body) else 0,
                       when=now)
    body = insert_built_line(body, built)
    # Reset -> kit tokens -> kit components -> project delta -> the page's own
    # <style>. Each layer may override the one before it, and the author's block
    # is last so a local rule still wins. Writing a page is writing content plus
    # class names; the boilerplate is no longer re-authored per artifact.
    built_meta = (f'<meta name="artifact-built" '
                  f'content="{esc(now.strftime(BUILT_FORMAT))}">')
    head_extra = "\n".join(p for p in (kit_head(), built_meta,
                                       round_meta(args.outfile, surface),
                                       profile_delta(ctx), head_extra) if p)
    body = "\n".join(p for p in (body, kit_script()) if p)
    doc = document(args.title, body, lang=lang,
                   favicon=args.favicon or profile_favicon(ctx) or "",
                   head_extra=head_extra)

    if not args.outfile:
        sys.stdout.write(doc)
        # A pipe has no path, so the `siblings` check has no directory to scan and the
        # caller is free to never run the check at all — which is what happened in 1 of 2
        # field probes. Make the omission audible instead of silent.
        print("NOTE: wrapped to stdout, so the artifact contract was NOT verified. "
              "Re-run with --out <file> to have it checked, or run check-artifact.sh "
              "on the file yourself.", file=sys.stderr)
        return 0

    # Create at most ONE missing level, and only when its own parent exists.
    #
    # The documented anchorless fallback writes to `.context/reports/`, a directory
    # that does not exist until the first report — so the procedure's own happy path
    # used to end in a traceback. But an unconditional makedirs is the wrong fix:
    # both failures observed in the field were a WRONG CWD, and makedirs would have
    # turned each into a silently misplaced file instead of an error. One level deep
    # tells the two apart, because a wrong cwd is missing more than the leaf.
    outdir = os.path.dirname(os.path.abspath(args.outfile))
    if not os.path.isdir(outdir):
        if os.path.isdir(os.path.dirname(outdir)):
            os.makedirs(outdir, exist_ok=True)
        else:
            print(f"ERROR: cannot write {args.outfile} — {outdir} does not exist and "
                  f"neither does its parent, so this is a wrong working directory "
                  f"rather than a first report (cwd={os.getcwd()})", file=sys.stderr)
            return 4

    # Refresh the lock BEFORE the page is written: the write is the event a watcher
    # sees, so a lock created after it has a window where the page looks final. On
    # every wrap of the build, not on the first one only — the guard is an age
    # (20 minutes in artifact-open-once.sh), so a build longer than that would
    # otherwise unlock itself halfway through. Best-effort, like the baseline: a
    # read-only tree must not fail a page that satisfies the contract.
    if args.building:
        try:
            os.makedirs(os.path.join(outdir, ".aidex-artifact-prev"), exist_ok=True)
            with open(lock_path(args.outfile), "w", encoding="utf-8") as fh:
                # The round this build started at, re-written unchanged on every
                # wrap of it (`shown_round` is read from this file above). The
                # first line is what artifact-open-once.sh and the tests know;
                # the number is additive.
                fh.write(f"building\n{shown_round}\n")
        except OSError as e:
            print(f"NOTE: could not write the build lock ({e}); this page can be "
                  f"opened as final while you are still writing it.", file=sys.stderr)

    # The baseline the id-stability rule compares against is the last PASSING
    # version, kept here, and NOT whatever happens to be on disk.
    #
    # A failing write used to be left in place so the author could fix it without
    # re-deriving the page. With only a temp snapshot, that made the violating
    # document the next run's baseline and inverted the gate: the author restoring
    # the correct title got the FIX reported as the violation, and re-running the
    # same violating content PASSED. One check, single-shot, self-erasing after
    # exactly the event it exists to catch. The failing render is rolled back off
    # `--out` now, so the snapshot is a passing version too — but the stored
    # baseline is still what the rule needs, because it survives the page being
    # deleted and re-created.
    #
    # A sibling directory rather than a sibling file, because check-artifact.sh's
    # own `siblings` rule scans the report's directory at depth 1.
    baseline_dir = os.path.join(outdir, ".aidex-artifact-prev")
    baseline = os.path.join(baseline_dir, os.path.basename(args.outfile))

    # Snapshot the version about to be replaced BEFORE overwriting it: the
    # stable-id rule is only checkable with both versions in hand, and one line
    # later there is no "before" left to compare against. This is the fallback for
    # a file that predates the stored baseline; when a baseline exists it wins.
    prev_snapshot = None
    # Read here, printed only once the wrap has passed: a failing wrap is rolled
    # back off `--out`, so the questions the reader is looking at did not change
    # after all. Compared against the render being REPLACED — what the reader
    # last saw, which is what his stored answers were fingerprinted against —
    # and not against the contract baseline. Under `--building` that is the
    # immediately previous wrap of the same build: the lock carries the round the
    # build started at and no render, so there is no build-start baseline to
    # compare with; the ids therefore name what the last wrap changed.
    rephrased = []
    if os.path.isfile(args.outfile):
        prev_text = open(args.outfile, encoding="utf-8", errors="replace").read()
        rephrased = changed_questions(prev_text, doc)
        fd, prev_snapshot = tempfile.mkstemp(suffix=".prev.html")
        os.close(fd)
        shutil.copyfile(args.outfile, prev_snapshot)
        if "<textarea" in prev_text.lower():
            # §8's warn-before-rewrite clause, narrowed since kit v4: the composer
            # keeps typed answers in localStorage keyed by this path and restores
            # them on reload, so the everyday loss case is gone. What remains is
            # the storage-less case — another browser/machine, a private window,
            # an engine refusing storage on file:// — and a pre-v4 page whose
            # composer never saved anything.
            print("NOTE: this path held a consultation page. Since kit v4 typed answers "
                  "are restored from this machine's browser storage on reload; they are "
                  "still lost on another browser/machine or if the page predates v4. "
                  "Since kit v6 an answer whose question you rephrased is deliberately "
                  "NOT restored — that item reads blank and the page's banner says so. "
                  "Since kit v7 an answer already SENT with the copy button does not "
                  "cross into a new round either; one typed and never sent still does.",
                  file=sys.stderr)

    with open(args.outfile, "w", encoding="utf-8") as fh:
        fh.write(doc)

    # `<page>.body` (`.body.md` for a markdown input) is the SOURCE OF THE PAGE that
    # is at `--out`, kept beside the baseline. A wrapped page is 100-200 KB of which
    # the author's content is 12-33%; without this a revision round loads the wrapped
    # file, carves the content back out and re-wraps it — the only way to double-wrap
    # a page, which the contract check passes.
    #
    # Written on a PASS only, and that is the whole invariant. It was written on every
    # wrap for one day; the 2026-09-20 review ran the consequence: a failing wrap is
    # rolled back off `--out`, so writing the attempt here destroyed the source of the
    # very version the rollback had just restored — and when the attempt was html over
    # a page wrapped from markdown, the "drop the other spelling" line deleted it
    # outright while stderr said the page was left exactly as it was. A failing
    # attempt never touches this name: it lives entirely under `.failed` (below).
    #
    # Inside the baseline directory because validate.py, _lib.sh and the audit readers
    # skip it by name; never `.html`, so no sweep takes it for an artifact.
    # Best-effort, as the baseline is.
    body_suffix = ".body.md" if raw_is_md else ".body"
    body_file = baseline + body_suffix

    checker = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "check-artifact.sh")
    checker_missing = not os.path.isfile(checker)

    # Everything that happens when this wrap does not land, in one place, because the
    # `finally` below has to be able to call it however the check ended — a checker
    # that raised, or a Ctrl-C between the run and the verdict, used to leave an
    # UNVERIFIED document at `--out`, which is the one state this mechanism exists to
    # make impossible.
    aftermath = {}

    def not_landed():
        """Take the failing render off `--out` and keep the attempt under `.failed`.

        `--out` goes back byte-for-byte to the version that was there before this
        wrap, or is removed when this wrap was the first at that path: the reader,
        and the session, often have that tab open, and a page that fails its
        contract must never be what sits there.

        The attempt is kept whole — the render AND its source — for the author only.
        Never `.html`: the neighbour sweep scans the directory for artifacts, and the
        baseline directory is the one place every reader already skips by name.
        """
        if aftermath:
            return
        failed_copy = baseline + ".failed"
        failed_body = failed_copy + body_suffix
        try:
            os.makedirs(baseline_dir, exist_ok=True)
            shutil.copyfile(args.outfile, failed_copy)
            for stale in (failed_copy + ".body", failed_copy + ".body.md"):
                if stale != failed_body and os.path.isfile(stale):
                    os.unlink(stale)
            with open(failed_body, "w", encoding="utf-8") as fh:
                fh.write(raw)
        except OSError as e:
            failed_copy = failed_body = None
            print(f"NOTE: could not keep this attempt at {baseline}.failed ({e}); it "
                  f"exists nowhere on disk now — keep what you wrote before re-running.",
                  file=sys.stderr)
        if prev_snapshot:
            shutil.copyfile(prev_snapshot, args.outfile)
        elif os.path.isfile(args.outfile):
            os.unlink(args.outfile)
        aftermath.update(restored=bool(prev_snapshot), render=failed_copy,
                         source=failed_body)

    # The id rule is judged against the last version that PASSED: the stored
    # baseline, or — for a page that predates baselines — the snapshot of whatever
    # was on disk before this wrap. Since the rollback, that snapshot is a passing
    # version in every case but one: the first wrap after this change over a page the
    # OLD code left failing at `--out`, which is a violating document with no
    # baseline beside it. It becomes the baseline as soon as one wrap passes.
    cmd = ["bash", checker, args.outfile]
    prev_for_check = baseline if os.path.isfile(baseline) else prev_snapshot
    if prev_for_check:
        cmd += ["--prev", prev_for_check]
    rc = None
    try:
        rc = 1 if checker_missing else subprocess.run(cmd).returncode
    finally:
        if rc != 0:
            not_landed()
        if prev_snapshot:
            os.unlink(prev_snapshot)

    # One sentence for both refusals, keyed on what the rollback actually did: a
    # caller told "nothing was left" re-derives a page that is sitting there intact.
    landed = (f"{os.path.abspath(args.outfile)} and its source were left exactly as "
              f"they were before this wrap"
              if aftermath.get("restored") else
              f"nothing was written at {os.path.abspath(args.outfile)} — this wrap "
              f"was the first at that path")
    if checker_missing:
        print(f"ERROR: check-artifact.sh is missing at {checker}, so the contract could "
              f"not be verified and {landed}.", file=sys.stderr)
        return 3
    if rc != 0:
        fix = (f"Fix {aftermath['source']} and wrap it again with --in"
               if aftermath.get("source") else "Fix what you wrote and wrap it again")
        where = (f" The render that failed is at {aftermath['render']} if you need to "
                 f"read it." if aftermath.get("render") else "")
        print(f"ERROR: this wrap FAILS the artifact contract above, so {landed}. {fix}; "
              f"do not open or hand over the failing render.{where}", file=sys.stderr)
        # The baseline is NOT advanced. That is the whole point: the next run
        # compares against the last version that passed, so restoring the correct
        # content passes and repeating the violation still fails.
        return 1

    # Passed, so this version's source becomes the page's source — and the attempt
    # that failed before it, render and source alike, is answered and goes.
    try:
        os.makedirs(baseline_dir, exist_ok=True)
        for stale in (baseline + ".body", baseline + ".body.md", baseline + ".failed",
                      baseline + ".failed.body", baseline + ".failed.body.md"):
            if stale != body_file and os.path.isfile(stale):
                os.unlink(stale)
                # The hygiene note calls this one work, not residue, and leaves the
                # choice to the author; taking it for them is right — the page
                # passed at this path — but doing so silently is not.
                if ".failed.body" in stale:
                    print(f"NOTE: the unfinished attempt kept at {stale} was superseded "
                          f"by this passing wrap and removed.", file=sys.stderr)
        with open(body_file, "w", encoding="utf-8") as fh:
            fh.write(raw)
    except OSError as e:
        print(f"NOTE: could not keep the page content at {body_file} ({e}); the next "
              f"revision will have to extract it from the wrapped file.", file=sys.stderr)

    # One line for the whole set: the writer is being told what to say in the
    # reply, and a note per item is a list he has to re-assemble himself.
    if rephrased:
        print(f"NOTE: the question of {', '.join(rephrased)} changed since the "
              f"previous render — answers the reader had typed there and not "
              f"sent will not restore.", file=sys.stderr)

    # Offered on a PASS only: a failing first wrap would otherwise spend the project's
    # single offer on an artifact that never existed.
    offer = style_profile_offer(ctx)
    if offer:
        print(offer, file=sys.stderr)

    # Say where it landed, absolutely, and only once something did. `--out` takes a
    # relative path in the documented flow, so a run standing in the wrong project
    # writes a perfectly valid report into a neighbour's `.context/` and exits 0 —
    # the one-level makedirs cannot tell that apart from a first report, and widening
    # it would break the primary placement (a report is a sibling of its anchor,
    # anywhere in the tree). Printing the resolved path is what makes the landing
    # visible, and it is this suite's own rule for consultation pages.
    print(os.path.abspath(args.outfile))
    # The page's own build line, verbatim, so the session can quote it in the
    # reply and the reader can compare it with what his tab is showing. The path
    # says which FILE; only this says which VERSION of it (BL-439).
    print(built)
    # Passed, so this version becomes the baseline. Best-effort: a read-only tree
    # is a real state (`style_profile_offer` guards for it too), and losing the
    # baseline degrades to the old snapshot behaviour rather than failing a page
    # that just satisfied the contract.
    try:
        os.makedirs(baseline_dir, exist_ok=True)
        shutil.copyfile(args.outfile, baseline)
    except OSError as e:
        print(f"NOTE: could not record the contract baseline at {baseline} ({e}); "
              f"the next run will compare against the file on disk instead.",
              file=sys.stderr)

    # The contract is re-judged where new work happens. It used to be evaluated
    # exactly once, at the wrap, so a rule added later left an existing page
    # silently out of contract forever — a field report passed at 10:31 and
    # failed by 20:15 the same day, invisibly. NOTE-only: this wrap's own file
    # passed, and a neighbour's drift must not block it. Waived drift stays
    # quiet, so the note cannot decay into a nag; best-effort, because a sweep
    # crash must never fail a page that just satisfied the contract.
    try:
        import check_artifact as ca
        proot = os.path.dirname(ctx) if ctx else None
        drifted, _ = ca.sweep_directory(
            outdir, exclude={os.path.abspath(args.outfile)},
            context_dir=ctx, project_root=proot)
        per = {}
        for check, rel, _msg in drifted:
            per.setdefault(rel, []).append(check)
        for rel, checks in sorted(per.items()):
            print(f"NOTE: neighbouring artifact {rel} no longer passes the "
                  f"contract ({len(checks)} violation(s): "
                  f"{', '.join(sorted(set(checks)))}) — the contract evolved "
                  f"since it was written. Re-wrap it, or record the drift as "
                  f"'artifact-<check> | {rel} | - | <reason>' in "
                  f".context/.aidex-waivers", file=sys.stderr)
        for note in ca.baseline_hygiene(outdir):
            print(f"NOTE [baselines]: {note}", file=sys.stderr)
    except Exception as e:                          # noqa: BLE001 — best-effort
        print(f"NOTE: the neighbour sweep did not run ({e})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    # `--done` takes no content and no title, so it cannot go through the wrap
    # parser at all; it is dispatched before it.
    sys.exit(end_build(sys.argv[1:]) if "--done" in sys.argv[1:] else main())
