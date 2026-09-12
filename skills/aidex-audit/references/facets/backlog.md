---
title: "backlog"
label: { en: "Backlog", es: "Backlog" }
lexicon:
  backlog: "backlog|BL-\\d|reg[íi]stralo|regist[rr]a (esto|eso)|para despu[ée]s"
  backlog:defer: "\\bpara m[aá]s adelante\\b|\\banota para luego\\b"
  backlog:sweep: "\\bsweep\\b|\\bbarrido\\b|\\bworklist\\b"
skills: [aidex-backlog]
slash: ["/aidex-backlog"]
scripts: [register-item.sh, define-item.sh, define-check.py, start-item.sh, defer-item.sh, triage.sh, quick-wins.py, normalize-language.sh, sweep-kickoff.sh, sweep-gate.sh, sweep-report.sh, sweep-eligible.py, sweep.sh, close-item.sh, reconcile.sh, harvest-commit.sh, detect-resolved.py]
paths: ["\\.context/backlog/", "\\.context/worklists/"]
primary_source: items
reader: read_sweep.py
sub_objectives: [intake, definition, triage, sweep, close]
---

# Backlog — analyst lens

One facet, five lifecycle stages. The tracked item is the unit: `mine_items.py` joins
each item to the sessions that registered, defined, triaged, swept and closed it, and
splitting the facet per stage would count that item five times (consultation
`2026-09-11-retro-por-aristas`, Q10). Every finding lands in exactly one stage.

| Stage | Scripts | What friction looks like |
|---|---|---|
| intake | `register-item.sh` | the gate of the system: one session in eight registers something; a refused or retried registration is a finding about the entry point |
| definition | `define-item.sh`, `define-check.py`, `start-item.sh`, `defer-item.sh` | items defined twice, `define-check` refusing what the user thinks is complete |
| triage | `triage.sh`, `quick-wins.py`, `normalize-language.sh` | the least exercised stage; silence here is a question, not a verdict |
| sweep | `sweep-kickoff.sh`, `sweep-gate.sh`, `sweep-report.sh`, `sweep-eligible.py`, `sweep.sh` | few sessions, many calls per session: a sweep is a run, not a gesture; read its worklist report (`read_sweep.py`) before the transcript |
| close | `close-item.sh`, `reconcile.sh`, `harvest-commit.sh`, `detect-resolved.py` | closure is almost always manual and per item; automatic detection is barely used |

Rules for the numbers:

- **Per session, never per call.** `close-item.sh` shows hundreds of consecutive
  retries; a call count measures the retry loop, not the usage.
- **Exit-2 refusals of `close-item.sh --sweep` are their own counter.** They are
  neither an error nor a retry: the script refusing to close outside a sweep is the
  designed behaviour, and counting them as failures inflates the close stage.
- A sweep report is disk residue: `read_sweep.py` prints one row per report and the
  count it processed. A report that says `PASS` and a transcript that re-dictated the
  gate three times are one finding with two sources, not two findings.
