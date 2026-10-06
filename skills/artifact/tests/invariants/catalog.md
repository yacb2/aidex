# Artifact invariant catalog (LOOP-008)

One row per invariant, decided on the RENDERED DOM after `composer.js` has run
(`scripts/render-probe.sh --invariants`, 1280 px). Rows are added with evidence and never
removed or weakened to make a gate pass. `invariant-gate.sh` counts the rows below.

Page kinds: presentation = any page; consultation = a page with at least one `.consult-item`
(galleries included, they are consultation items). "Rail" = `#raillist`; every NAV row applies
only to a page that has one. Probe functions are the keys of `invariants()` in
`scripts/render-probe.mjs` (the RUN rows are the listeners in the `--invariants` loop).
RED fixtures are page BODIES under `tests/fixtures/invariants/` (`<ID>.html`, extra reviewer
counterexamples as `<ID>.<tag>.html`), wrapped by `tests/test-invariants.sh` with the current kit.

| id | statement | kinds | probe | RED fixture |
|---|---|---|---|---|
| NAV-1 | Every rail entry's `href="#x"` resolves to an element whose id is `x`. | presentation, consultation | invariants:NAV-1 | tests/fixtures/invariants/NAV-1.html |
| NAV-2 | No rail entry targets an element that is not rendered (`checkVisibility()` false). A closed `details` is NOT an exemption: the composer never opens one on rail navigation. A decided target is NAV-8's. | presentation, consultation | invariants:NAV-2 | tests/fixtures/invariants/NAV-2.html, NAV-2.b6.html |
| NAV-3 | Rail entries appear in the document order of their targets: no entry's target precedes the previous entry's target (a target that contains the previous one counts as preceding it). Decided targets (NAV-8) are left out of the order. | presentation, consultation | invariants:NAV-3 | tests/fixtures/invariants/NAV-3.html |
| NAV-4 | Every rail label (`.rt`) is non-empty and equals, case and whitespace folded, the target's OWN heading (`:scope > .sec-head h2`, `> h2` or `> h3`, without the `.consult-id` badge); a prefix match is allowed only when the label ends in an explicit truncation marker (`…` or `...`). A target with no own heading falls back to the label appearing in its text. This is what catches an item whose `data-title` (the rail label) is never visible text. | presentation, consultation | invariants:NAV-4 | tests/fixtures/invariants/NAV-4.html, NAV-4.b2.html |
| NAV-5 | Every rendered `h2` in `.main` outside a closed `details` is a rail target or the FIRST `h2` of one (a second `h2` inside a listed section has no entry of its own). | presentation, consultation | invariants:NAV-5 | tests/fixtures/invariants/NAV-5.html, NAV-5.b1.html |
| NAV-6 | No two rail entries share a target id. | presentation, consultation | invariants:NAV-6 | tests/fixtures/invariants/NAV-6.html |
| NAV-7 | No element id is carried by two elements in the document (on any page, rail or not). | presentation, consultation | invariants:NAV-7 | tests/fixtures/invariants/NAV-7.html |
| NAV-8 | No rail entry targets a decided item (`[data-decided]` without `data-proposal`) or anything inside `details.decided-unit`: the composer folds those out of the index. | consultation | invariants:NAV-8 | tests/fixtures/invariants/NAV-8.html |
| NAV-9 | Every rendered `.consult-item` outside a closed `details` that is not settled (no `data-decided`, or `data-decided` with `data-proposal`) is the target of some rail entry. Composer exemption stated: a proposal inside a `.consult-group` gets no entry (`itemLink`: decided and in a group). An item whose group has no `id` is the defect this row catches: the composer only lists `.main > section[id]`, so its items never get an entry. | consultation | invariants:NAV-9 | tests/fixtures/invariants/NAV-9.html, NAV-9.c3.html |
| CON-1 | Every `.consult-item` that asks (not `.consult-notes`, not a gallery sample with no `.opts`, not `data-decided`, not `data-free` with a value other than `no`/`false`) has at least 2 authored options in its own subtree: radio or checkbox inputs inside `.opts` (not the composer's `.kit-other` / `.kit-notnow`, not `[data-other]`), or the largest `select`'s options. An item with no `.opts` at all counts 0. Mirrors `contract_defects.check_decision_item_without_options`; what it adds over that static check is the RENDERED DOM: hand-edited built HTML and gallery rows on consultation pages are judged as the reader gets them. | consultation | invariants:CON-1 | tests/fixtures/invariants/CON-1.html, CON-1.b5.html |
| CON-2 | The page has exactly one `#consult-copy` inside `aside.rail` and exactly one `#consult-copy-end` inside `main`. | consultation | invariants:CON-2 | tests/fixtures/invariants/CON-2.html |
| CON-3 | No `.consult-item` is empty: after removing its `.consult-id` badge, `.fieldlabel` texts, textareas and the composer's own chrome list (composer.js `questionHash`: `.kit-tag, .consult-proposal, .consult-clear, .kit-other, .kit-notnow, .kit-ask, .kit-more, .kit-provisional, .kit-marks-tile, .kit-marks-list, details.opts-more > summary`; `test-invariants.sh` checks the probe copy against composer.js) it still has text or an input, img, svg, table, figure, canvas, video, pre or select. | consultation | invariants:CON-3 | tests/fixtures/invariants/CON-3.html, CON-3.c2.html |
| CNT-1 | No prose contains the literal spec syntax `:::` or `{#` (text inside code, pre, kbd, samp, textarea, script, style, template, an element or ancestor with `[hidden]` whose computed display is none, or any display:none outside a details, is exempt (`[hidden]` alone is not: the kit's `.main > section {display:flex}` overrides it); a closed `details` and the composer's folded decided units are NOT exempt). | presentation, consultation | invariants:CNT-1 | tests/fixtures/invariants/CNT-1.html |
| CNT-2 | No prose contains an unrendered markdown marker: `**` or a backtick (same exemptions and same reach as CNT-1, folded details included; a `[hidden]` section the kit still shows is judged). | presentation, consultation | invariants:CNT-2 | tests/fixtures/invariants/CNT-2.html, CNT-2.b4.html, CNT-2.b7.html, CNT-2.c4.html |
| CNT-3 | No rendered `section` under `.main`, `.callout` or `.note` is empty: after removing its `.sec-head`, `h2`, `h3` and `.eyebrow` it has text, or an svg, img, table, figure, canvas, video, iframe, input, textarea, select or pre (a `.consult-item` is CON-3's). | presentation, consultation | invariants:CNT-3 | tests/fixtures/invariants/CNT-3.html, CNT-3.b3.html |
| RUN-1 | The page logs no console error (a failed resource load is RUN-3's, not counted here). | presentation, consultation | listener:console | tests/fixtures/invariants/RUN-1.html |
| RUN-2 | The page raises no uncaught exception (`pageerror`). | presentation, consultation | listener:pageerror | tests/fixtures/invariants/RUN-2.html |
| RUN-3 | No request fails and no response has status >= 400. | presentation, consultation | listener:requestfailed, response | tests/fixtures/invariants/RUN-3.html |
| LANG-1 | When the kit chrome (`.railhead`, `#consult-copy`) is exactly a string of some language in the page's own `STRINGS` table, `<html lang>` (first two letters, lowercase) is one of those languages. A chrome the author rewrote matches nothing and is not judged. RED: an authored Spanish `.railhead` "Contenido" under `lang="en"` (the fixture's first line `<!-- wrap-lang: en -->` sets the wrap language). | presentation, consultation | invariants:LANG-1 | tests/fixtures/invariants/LANG-1.html |

## Known gaps (not decided by any row today)

- NAV-4 containment fallback: when a rail target has no own heading by the NAV-4 selectors
  (`:scope > .sec-head h2`, `> h2`, `> h3`), the check falls back to "the label appears in the
  target's text", so a label that is only an option text passes. Only hand-written HTML reaches it
  (the builder always emits an own heading). Example: `tests/fixtures/invariants/gaps/NAV-4.c4.html`
  (heading wrapped in `div.head`, `data-title` equal to an option label): clean today, wrongly.
