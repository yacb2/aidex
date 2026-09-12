---
title: "artifacts"
label: { en: "Artifacts", es: "Artefactos" }
lexicon:
  artifact:page: "\\bartifacts?\\b|\\bartefactos?\\b|\\bp[aá]gina de consulta\\b|\\bconsultation\\b|\\bwrap(-report)?\\b|check-artifact"
skills: [artifact-design, artifact-diagramming, aidex-dash]
slash: ["/aidex-dash"]
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
| consult | how many rounds a consultation took to reach every item decided; which items stayed open | page residue (`consult-round`, `data-decided`) |
| re-judge | which old pages fail today's checker, and under which kit version they were written | reader output grouped by version band |

Rules:

- **Group by version band, never "pages fail".** A page written under kit v9 failing
  a v18 rule is a finding about v9 to v12 pages; the reader carries the band on every
  failure line, and the finding names it.
- **`_archive/` is in scope for the reader and out of scope for the census.**
  `check-artifact.sh --census` skips `_archive/` and `.aidex-artifact-prev/` by
  design; the reader runs the checker per file so archived pages are read without
  making the census the instrument.
- **One finding per page.** A prompt complaining about a page and the same page
  failing the checker are one finding with two sources; the synthesis unites them.
