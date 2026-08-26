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
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from _shell import document, esc  # noqa: E402

LEADING_STYLE = re.compile(r"\A\s*((?:<style\b[^>]*>.*?</style>\s*)+)", re.S | re.I)
# `- language: es` in the project style profile. A FIELD, not prose: the prose
# form sat in the template for weeks and nothing could read it.
LANG_FIELD = re.compile(r"^\s*[-*]?\s*language\s*:\s*([A-Za-z][A-Za-z0-9-]*)", re.M)
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


# .../skills/aidex-dash/scripts/dash/wrap_report.py -> .../skills
_SKILLS_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                           os.pardir, os.pardir, os.pardir))
LIB_SH = os.path.join(_SKILLS_DIR, "aidex-conventions", "scripts", "_lib.sh")


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


def round_meta(outfile):
    """`<meta name="consult-round">` for the page about to be written.

    What it is for: the composer keeps typed answers in localStorage and used to
    restore them into every later regeneration, so notes the session had already
    read and acted on were handed back to the reader round after round. The
    marker is how the page tells "the reader reloaded me" from "this is a new
    round"; the composer then drops only what was already SENT (see composer.js
    § the ROUND).

    Derived from the BASELINE, never from the file on disk. A wrap that fails
    the contract leaves its output in place deliberately and does NOT advance the
    baseline, so counting from disk would increment twice across a failed wrap
    and a fixed one — blanking sent-answer state on a round the reader never saw.
    The on-disk file is only the fallback for a page written before baselines
    existed.

    A wrap to stdout has no path and therefore no round. That is correct rather
    than a gap: without `--out` there is no thread to be a round of, and a page
    with no marker keeps the pre-round behaviour exactly.
    """
    if not outfile:
        return ""
    out = os.path.abspath(outfile)
    baseline = os.path.join(os.path.dirname(out), ".aidex-artifact-prev",
                            os.path.basename(out))
    if os.path.isfile(baseline):
        prev = _round_of(baseline) or 1
    elif os.path.isfile(out):
        prev = _round_of(out) or 1
    else:
        prev = 0
    return f'<meta name="consult-round" content="{prev + 1}">'


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


def profile_language(ctx):
    """The project's configured artifact language, or None.

    Scope is ARTIFACTS. `.context/` stays English (D-04) whatever this says, and
    `communications/` keep the language they arrived in — this field only decides
    what a report a human reads is written in.
    """
    text = _profile_text(ctx)
    if not text:
        return None
    m = LANG_FIELD.search(text)
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
            "aidex-dash/assets/templates/artifact-style.md.template, prefilled with the "
            "choices just made. Do not create it unasked. This offer is now recorded in "
            f"{marker} and will not fire again.")


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
    args = p.parse_args()

    content = (open(args.infile, encoding="utf-8").read() if args.infile
               else sys.stdin.read())
    if not content.strip():
        print("ERROR: no content on stdin (nothing to wrap)", file=sys.stderr)
        return 2
    if re.search(r"<!doctype\s+html", content, re.I):
        print("ERROR: content already has a doctype — pass page content only, "
              "not a full document", file=sys.stderr)
        return 2

    # The style profile is looked up from where the artifact LANDS, not from the
    # cwd: a report is a sibling of its anchor and can be written into a project
    # the run is not standing in.
    ctx = find_context_dir(os.path.dirname(os.path.abspath(args.outfile))
                           if args.outfile else os.getcwd())
    lang = args.lang or profile_language(ctx) or "en"

    head_extra, body = split_head_style(content)
    # Reset -> kit tokens -> kit components -> project delta -> the page's own
    # <style>. Each layer may override the one before it, and the author's block
    # is last so a local rule still wins. Writing a page is writing content plus
    # class names; the boilerplate is no longer re-authored per artifact.
    head_extra = "\n".join(p for p in (kit_head(), round_meta(args.outfile),
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

    # The baseline the id-stability rule compares against is the last PASSING
    # version, kept here, and NOT whatever happens to be on disk.
    #
    # A failing write is deliberately left in place so the author can fix it
    # without re-deriving the page. With only a temp snapshot, that made the
    # violating document the next run's baseline and inverted the gate: the author
    # restoring the correct title got the FIX reported as the violation, and
    # re-running the same violating content PASSED. One check, single-shot,
    # self-erasing after exactly the event it exists to catch.
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
    if os.path.isfile(args.outfile):
        prev_text = open(args.outfile, encoding="utf-8", errors="replace").read()
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

    offer = style_profile_offer(ctx)
    if offer:
        print(offer, file=sys.stderr)

    checker = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "check-artifact.sh")
    if not os.path.isfile(checker):
        print(f"ERROR: wrote {args.outfile} but check-artifact.sh is missing at {checker} "
              f"— the contract was not verified", file=sys.stderr)
        return 3
    # Say where it landed, absolutely. `--out` takes a relative path in the
    # documented flow, so a run standing in the wrong project writes a perfectly
    # valid report into a neighbour's `.context/` and exits 0 — the one-level
    # makedirs cannot tell that apart from a first report, and widening it would
    # break the primary placement (a report is a sibling of its anchor, anywhere
    # in the tree). Printing the resolved path is what makes the landing visible,
    # and it is this suite's own rule for consultation pages.
    print(os.path.abspath(args.outfile))

    cmd = ["bash", checker, args.outfile]
    prev_for_check = baseline if os.path.isfile(baseline) else prev_snapshot
    if prev_for_check:
        cmd += ["--prev", prev_for_check]
    try:
        rc = subprocess.run(cmd).returncode
    finally:
        if prev_snapshot:
            os.unlink(prev_snapshot)
    if rc != 0:
        print(f"ERROR: {args.outfile} was written but FAILS the artifact contract above. "
              f"Fix the content and re-run; do not open or hand over this file.",
              file=sys.stderr)
        # The baseline is NOT advanced. That is the whole point: the next run
        # compares against the last version that passed, so restoring the correct
        # content passes and repeating the violation still fails.
        return 1
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
    sys.exit(main())
