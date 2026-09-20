---
title: "artifacts"
label: { en: "Artifacts", es: "Artefactos" }
lexicon:
  artifact:page: "\\bartifacts?\\b|\\bartefactos?\\b|\\bp[aá]gina de consulta\\b|\\bconsultation\\b|\\bwrap(-report)?\\b|check-artifact"
skills: [artifact-design, artifact-diagramming, artifact]
slash: ["/aidex:artifact"]
scripts: [wrap-report.sh, check-artifact.sh, render.sh]
paths: ["\\.context/reports/", "\\.html$"]
primary_source: pages
reader: read_artifacts.py
sub_objectives: [wrap, consult, re-judge]
---

# Artifacts — analyst lens

The best residue in the suite: every wrapped page carries `<meta name="artifact-kit">`
with the kit version that wrote it, the consult round, its items and which of them are
decided. Start from the pages (`read_artifacts.py`), then open only the sessions the
join attributes to a page, for the *why* behind a correction.

| Sub-objective | Question | Source |
|---|---|---|
| wrap | did `wrap-report.sh` do what was asked first time, or was the page re-wrapped after a check failure | tool events (`wrap-report.sh`, `check-artifact.sh`, exit codes) plus the session's prompts |
| consult | the round the page has reached, and the round its QUESTIONS were decided in — `decided-round N` (the last question was decided in round N), `not-all-decided`, `no-items`, or `unknown`; the question set excludes the block (`.consult-group`) and the mandatory `notes` item, as the checker's own item rules do | page residue (`consult-round`, `data-decided`, `data-decided-round`) |
| re-judge | which old pages fail today's checker, and under which kit version they were written | reader output grouped by version band |

Rules:

- **`unknown` is not round 1, and it does not heal.** `data-decided-round` is
  stamped per item by the wrapper since BL-421, at the moment the item is decided.
  A page whose items were already decided before that keeps NO stamp on them even
  after it is re-wrapped — the round they were decided in was never recorded, and
  the wrapper refuses to answer with the round that happens to migrate the page.
  The reader says `unknown`. A rounds-to-decided figure counts the pages it can
  read and states how many it could not; folding `unknown` into round 1 would make
  the oldest pages the fastest consultations in the corpus. Only items decided (or
  re-decided with a different verdict) from now on carry a round.

- **Group by version band, never "pages fail".** A page written under kit v9 failing
  a v18 rule is a finding about v9 to v12 pages; the reader carries the band on every
  failure line, and the finding names it.
- **`_archive/` is in scope for the reader and out of scope for the census.**
  `check-artifact.sh --census` skips `_archive/` and `.aidex-artifact-prev/` by
  design; the reader runs the checker per file so archived pages are read without
  making the census the instrument.
- **One finding per page.** A prompt complaining about a page and the same page
  failing the checker are one finding with two sources; the synthesis unites them.
