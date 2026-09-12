# Guided human verification at the integration boundary

Shared canon. Consumers: `aidex-plan-exec` (close-out step 7), `aidex-bugfix`
(step 8) and `aidex-backlog`'s sweep run mode (`sweep-execution-policy.md`, close-out).
None restates it — a restated protocol is a second place to drift.

## Why this is a step and not guidance

Verification that only a human can do — a flow clicked through, a screen actually
looked at — had no place to happen and no way to leave a trace. Guidance written down
does not get adopted; a step sited at a gate does, because the gate is already being run.

## Where it fires

**The integration boundary** — the same boundary the full suite gates:
merge to trunk, push, deploy, release, **or the end of a run**
(`decision/2026-08-24-full-suite-gate-moves-from-commit-to-integration`).

The last of those is the one that fires in the normal path, and it is worth being
explicit about why: close-out **does not merge**. A run finishes by leaving the branch
ready to merge (`rules/autonomy.md` § Integrating a branch is not a commit), so a step
sited "at the merge" would never run inside the run that produced the work. It fires at
the end of the run, before the branch is handed over.

It fires **once**, at that boundary — not per phase and not per commit. A phase's own
verification is the selected suite and its proof; this is the last thing before the work
leaves the review window.

## The four moves, in order

1. **Suites first.** The full-suite gate has already run at this boundary. Its output is
   evidence for the checklist below, not something to re-run here.
2. **Claude smoke-tests everything mechanically checkable** — browser automation (Chrome
   DevTools MCP or the project's own tooling) until every behavior a machine can check is
   verified. The human must never be the first to find a broken click. For responsive
   checks, **emulate the viewport**: a narrow desktop window is not a phone and reads as
   a squashed layout to whoever is watching.
3. **Leave a visible browser window open** on the changed feature, signed in, positioned
   where the review starts — in the browser the person actually watches, never a headless
   or background context ("¿dónde lo estás viendo?" is this step failing).
4. **Hand over a written checklist of only what a human must judge** — visual feel, UX,
   wording, anything that cannot be reproduced or evaluated mechanically. Everything
   already machine-verified is listed as **done, with its evidence**, not re-delegated.
   That is the HITL division of labour: the person judges what needs eyes; nothing
   100%-checkable is theirs to re-check.

## It emits a proof artifact

The checklist is **a durable written record linked from `proof_links`** (`00-global.md`
§7.1). Without this the verification happens and then vanishes with the session, which is
the failure mode the whole step exists to close. The record takes one of two shapes,
by consumer:

- **A plan or a bug fix** writes `.context/proofs/<slug>/human-verification.md`.
- **A sweep** does not write that file per item. Its owner rows live in each item's
  `## Verification` table (`kind: owner`, proof empty until the owner answers) and
  `sweep-report.sh` aggregates every owner row across the run into one list — one artifact
  per run, not one per item, so the owner answers in one place instead of across N stray
  files. `worklist-close.sh` refuses to end the run while an owner row is unanswered.

The file carries three parts:

```
## Machine-verified   <what was checked, each with its evidence>
## For a human        <the items only eyes can settle, unchecked>
## Verdict            <who looked, on what date, and what they said>
```

Either shape is **wrapped into a page at close-out and opened once** — `wrap-report.sh
--title "<the page title>" --lang en --in <the .md> --out <the .html>`, then `open`,
last, per `rules/artifacts-local-first.md` gate 2 (never published, gate 3).

Both flags are load-bearing and the command fails without them, in different ways.
`--title` is `required=True`, so omitting it aborts on an argparse usage error before
anything is written — and it doubles as the fallback `<h1>`, since a
`human-verification.md` carries no `# ` line and the page would otherwise have no heading
and an empty rail. `--lang en` is needed because this artifact is a `.context/` document
and those are English by D-04, while `--lang` defaults to the project's
`artifact-style.md`: in a project whose profile declares another language the wrap writes
`<html lang="es">` over an English body and `check-artifact.sh` fails it (`lang`, BL-279).
Measured in aidex on 2026-09-08 — the same command minus `--lang` failed with
`<html lang="es"> but the body reads en (17 Spanish vs 1329 English stopwords)`.
`sweep-report.sh` passes `--lang en` for exactly this reason. The markdown stays the canon and the `proof_links`
target; the page is the medium the reader actually reads. This is not a nicety: a session
that handed over `human-verification.md` was asked for "the artifact" on the very next
turn, and that class — summarise the run you just finished — was the second most common
artifact request measured across the corpus (BL-345).

Write the first two parts **before** handing over; the verdict is appended when the
answer comes back. A checklist handed over and never answered is a legitimate end state
for a run — the artifact records that it is outstanding, which a chat message does not.

## Skipping is allowed. Skipping silently is not

Most work is not human-visible: a tooling change, a script, a refactor behind a stable
interface. Skipping is the right call there and needs no permission — but it is
**recorded**, one line, naming the reason:

```
human-verification: skipped — <why nothing here is human-visible>
```

in the same `.context/proofs/<slug>/` location (or the plan's Execution log; for a sweep,
the report carries the line verbatim), so a reader
can tell "nothing a person operates changed" apart from "nobody thought about it". Those
two look identical when the step is simply absent, and only one of them is fine.

An unrecorded carve-out is the failure this rule names, not an exemption it grants: a
bare *skip for backend/tooling work* clause reads as legitimate and is exactly how the
step goes missing. If the reason is not written down, the step was not skipped — it was
forgotten.

## A claim is backed by a fresh run, shown

"Tests pass", "build succeeds", "the bug is fixed" mean the command was run in this
session and its output is in the reply. A remembered or cached result is not evidence;
neither is "should work" or "looks correct".

## NEVER (destructive verification)

- **Never run a delete to test it.** A `prune --filter` whose filter silently fails to
  match still deletes, and there is no dry run — "testing" it *is* the destructive act.
  The standing requirement is "¿puedes comprobar sin eliminar nada?".
- Instead: enumerate read-only first, show the exact ids, confirm the complement is
  empty, then delete **by explicit id** — never by prune or filter. Re-verify immediately
  before deleting, not just at analysis time, and build enumerate-then-remove into any
  generated script.

## What counts as evidence

- Before citing a green gate, show it saw **non-empty input**: print the count it
  processed, or make it fail once on purpose. A gate that silently processed nothing
  (a lint whose config ignored the whole directory, an E2E suite run against a stale
  image) is green and indistinguishable from a real pass. When adding a gate, make it
  say how much it saw, and assert the tricky case at the **consumer's** seam, not only
  where it is known.
- Run a silent-on-failure check **bare**, never through a pipe. `manage.py migrate
  --check` prints nothing when migrations are pending — its whole verdict is the exit
  code, and a pipeline reports the last stage's status instead. Capture to a file and
  check `$?` before filtering.
- Prove a RED is genuine before you believe it: `git stash push -- <only the fix files>`,
  run the test, confirm it fails **for the right reason**, then pop. A security test can
  pass without the fix because the framework already rejected the case one layer down.
- For commands that can succeed partially (migrations, batch jobs, bulk imports, data backfills): exit code 0 is not enough. Verify counts/state before vs after, or check for skipped/failed records in logs. A "completed successfully" message that hides 14% skipped rows is a silent failure.
