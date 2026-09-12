---
title: "planning"
label: { en: "Planning", es: "Planificación" }
lexicon:
  plan:context: "\\.context|plan formal|documenta (esto|el plan)|seg[uú]n (el )?est[áa]ndar"
  plan:ask: "\\bplan(ea|ifica)?\\b|\\bvamos a planear\\b|\\bmulti-?fase\\b|\\bplan-exec\\b"
skills: [plan, plan-exec]
slash: ["/aidex:plan", "/aidex:plan-exec"]
scripts: [worklist-advance.sh, close-plan.sh, reindex-plans.sh]
paths: ["\\.context/plans/", "\\.context/worklists/"]
primary_source: transcript
sub_objectives: [plan, execute, close]
---

# Planning — analyst lens

A plan has one session where it is written and several where it is executed, and only
a minority of plans carry an execution log, so the transcript is primary:
`mine_items.py` already builds the spans per plan and tells a planning span from an
execution span by the skill that fired in it. No residue reader: the plan files say
what was planned, not how the run went.

| Sub-objective | Question |
|---|---|
| plan | did `plan` produce a plan the user accepted, or was it re-triaged, re-scoped or rewritten by hand |
| execute | did `plan-exec` run the phases start to finish; where did it stop to ask, and was the question one the plan should have settled |
| close | did the run reach close-out (`close-plan.sh`), and were deferrals registered or left as prose |

Rules:

- **`worklist-advance.sh` is shared.** It lives in `conventions` and the backlog
  sweep uses it too; an event on it counts for planning only in a session where a
  planning skill fired, otherwise it belongs to the sweep stage of the backlog facet.
- **Several sessions per plan.** Read the spans in order; a friction in the third
  execution session about a decision taken in the planning session is a planning
  finding, not an execution one.
