# Sketch rounds: the screen kit and who captures

Owned by SKILL.md Step 0 (sketch mode). Measured on echo_lab BL-750 (LOOP-007, n=2 per
variant): a re-capture round went from 11.2 min / $1.15 to 3.2 min / $0.40, a first build
from 11.1 / $1.53 to 8.9 / $1.39. Gate checks stayed green on every variant.

## Who does what

| Round | Agent | Reads | Does |
|---|---|---|---|
| Re-capture (the screen's gallery spec exists) | the sketch round's impl agent | the screen's `gallery-kit.md` + the project `.context/ui-contract.md` | the app change, the spec edit, the one capture, the rows JSON, the kit rewrite |
| First build | `aidex:gallery-builder` | the project file + the pattern spec (kit if one exists) | the spec, fixtures, the one capture, rows JSON, the kit |

No gallery-builder hop on a re-capture: a second agent re-reads the kit, and the
implementer's own no-update run only rediscovers the expected label failures.
The capturing agent reads the kit and the project file, never the harness contract or
sibling specs.

## One capture run per round

`--update-snapshots`, spec path BEFORE the flags, no no-update run first, no confirmation
run (the confirmation is the hardening gate; harness contract § 2b labels the run "not a
gate run"). Before it, copy the current baselines aside: they are the round's BEFORE. A
dropped cell's baseline is removed by hand after the copy.

## The kit: `gallery-kit.md` in the consultation folder

Written at the first build, rewritten by the capturing agent at every hand-back, passed in
every brief of the round. It holds only what is specific to the screen:

- worktree root, spec path (cells, slug), fixtures path, baselines path;
- the scoped capture command and the last run's closing line, with which pictures changed,
  which are new, which are byte-identical;
- screen facts for the round (labels with i18n keys, gate conditions, route guards);
- a cell table: cell, route, drive, what makes it distinct from its nearest neighbour;
- pitfalls hit this round with file:line (the project-wide ones are appended to the project
  file instead) and "read before reviewing the pictures" notes (harness masks, persona names).

The AFTER never waits for the BEFORE capture.

## Unrequested rows

The agent that makes the change also writes the rows, and tends to list only what was
asked. Measured: all 8 A reps renamed a shared label key that also changed a dialog title
and button; with a separate re-capture agent the rows flagged those cells `unrequested`
4/4, with the impl agent doing its own rows 0/4. So: every row whose visible change the
owner's answer did not ask for gets `kind: "unrequested"` and a `look` line naming it.
