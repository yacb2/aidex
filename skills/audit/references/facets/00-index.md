# Facets of the aidex suite — spec files for `usage-retro --facet`

A facet is one slice of the suite that `usage-retro` can analyse on its own (plan
`usage-retro-facets`, consultation `2026-09-11-retro-por-aristas`). Each facet is one
file in this folder, `<name>.md`, read by `scripts/usage-retro/facets.py`. The file is
the **single owner** of its lexicon entries: `prefilter.py` and `mine_repetition.py`
import them and keep only a `RESIDUAL` dict for entries no facet claims;
`tests/test-facet-lexicon-lockstep.sh` fails when a label lives in both places.

## Schema

```yaml
---
title: "artifacts"           # English identifier == filename stem
label: { en: "Artifacts", es: "Artefactos" }
lexicon:                     # label -> regex, re.I; the ONLY owner of these entries
  artifact:page: "\\bartifact\\b|\\bartefacto\\b|\\bp[aá]gina de consulta\\b"
skills: [artifact-design, artifact-diagramming, artifact]
slash: ["/aidex:artifact"]
scripts: [wrap-report.sh, check-artifact.sh, render.sh]
paths: ["\\.context/reports/", "\\.html$"]
primary_source: pages        # pages | transcript | items | events
reader: read_artifacts.py    # optional; lives in scripts/usage-retro/facets/
sub_objectives: [wrap, consult, re-judge]
---
<lens body: the analyst brief for this facet, handed to each shard verbatim>
```

| Key | Required | Shape | Meaning |
|---|---|---|---|
| `title` | yes | scalar, equals the filename stem | English identifier used in `facet:<name>` tags and run folders |
| `label` | yes | flow map `{ en, es }` | visible label; identifiers never localise, labels do |
| `lexicon` | yes | block map `label: "regex"` | prompt-side membership; double-quote and escape backslashes |
| `skills` | yes | flow list | skills whose firing (or prior firing) admits a row; each also gets `miss?:<skill>` from the facet regexes |
| `slash` | yes | flow list | slash commands that admit a row on their own |
| `scripts` | yes | flow list | script basenames counted as this facet's tool events |
| `paths` | yes | flow list of regexes | paths that mark a tool event as this facet's |
| `primary_source` | yes | `pages` / `transcript` / `items` / `events` | what the coverage gap is measured against; only disk residue (`pages`, `items`) gets a gap cell |
| `reader` | no | script name under `scripts/usage-retro/facets/` | residue reader; must print how many objects it processed |
| `sub_objectives` | no | flow list | the lifecycle stages or sub-goals the synthesis groups by |

A missing required key, a `title` that differs from the filename, an unknown
`primary_source`, a regex that does not compile, or a lexicon label owned by two facets
is a hard error: the loader never defaults.

## Admission

`prefilter.py` admits a row through the fifth gate when its prompt matches the facet
lexicon, its `skills_fired` or `prior_skills` name a facet skill, or its prompt is a
facet slash command; the row is tagged `facet:<name>` (several allowed). The summary
reports, per facet, rows admitted and rows admitted by the facet alone. `--facet NAME`
keeps only rows tagged with that facet (the facet run's view); without it every facet is
tagged.

## Facets

| Facet | Primary source | Reader | Sub-objectives |
|---|---|---|---|
| `backlog.md` | items | `read_sweep.py` | intake, definition, triage, sweep, close |
| `artifacts.md` | pages | `read_artifacts.py` | wrap, consult, re-judge |
| `session.md` | transcript | — | kickoff, re-dictation, continuation |
| `planning.md` | transcript | — | plan, execute, close |

Second batch, not yet defined: `worktree` and `validation` enter once tool events
measure them on real usage (consultation Q16). Run one facet with
`scripts/usage-retro/facet-run.sh <name> [--since X] [--until Y]`.

Point the loader elsewhere with `AIDEX_FACETS_DIR` (the lockstep test builds a temporary
facet directory; the repo ships no placeholder facet).
