# Define run mode (`/aidex-backlog define`)

A sweep **chooses** among defined items; it does not define them. The contract — `type`,
`priority`, `estimate`, `surface`, `verify`, `touches`, `## Context`, `## Acceptance` with
a real criterion — is § Definition contract of
[01-backlog-conventions.md](01-backlog-conventions.md); an item
below it is NEEDS-DECISION for `sweep-eligible.py` and `triage.sh` reports the count.
The run: `define-check.py` (read-only — what each item lacks, what its body already
tells a script: touches candidates, cross-repo paths, cited ids, clusters); then, per
underdefined item, read the item **and the code it names**, and write the verdict with
`define-item.sh` — `estimate` and `## Acceptance` included, without asking (owner's
call 2026-08-27; a wrong size only defers at the sweep). What stays the owner's:
`priority`, a hold, a cost decision — write it as `blocked_by` or an `owner` row, never
as a guess. Clusters that read as one change get `depends: merge:BL-NNN`; ones that
merely share a file get the same `touches` token and the sweep orders them adjacently.
