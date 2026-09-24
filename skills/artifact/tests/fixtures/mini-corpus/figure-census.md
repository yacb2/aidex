# Synthetic figure census

Test input for `test-goal-gate.sh`: the machine block `goal_gate.census_records()`
parses, over the three invented pages of this mini corpus. Every figure is
recorded, once: `alpha` draws a row diagram, `beta` a bar chart and then a
before-after diagram, `gamma` a line chart. All four are rung 1 and carried, so
the synthetic gate reads `figures: 4/4`. The real census lives in the corpus,
outside this repo.

<!-- FIGURE-CENSUS v2 figures=4 extensions= -->
```census
page=alpha/reports/2026-01-01-one-flow.html fig=1 kind=flow rung=1 block=diagram as=row
page=beta/reports/2026-01-02-two-figures.html fig=1 kind=chart rung=1 block=chart as=bar
page=beta/reports/2026-01-02-two-figures.html fig=2 kind=flow rung=1 block=diagram as=before-after
page=gamma/reports/2026-01-03-chart-only.html fig=1 kind=chart rung=1 block=chart as=line
```
