# Verification Before Completion Claims

## NEVER

- Claim "tests pass", "build succeeds", or "bug is fixed" without running the verification command and showing output
- Trust cached or remembered results — always run fresh
- Say "should work", "looks correct", or express satisfaction without evidence

## NEVER (destructive verification)

- **Never run a delete to test it.** A `prune --filter` whose filter silently fails to
  match still deletes, and there is no dry run — "testing" it *is* the destructive act.
  The standing requirement is "¿puedes comprobar sin eliminar nada?".
- Instead: enumerate read-only first, show the exact ids, confirm the complement is
  empty, then delete **by explicit id** — never by prune or filter. Re-verify immediately
  before deleting, not just at analysis time, and build enumerate-then-remove into any
  generated script.

## ALWAYS

- Before claiming tests pass: execute the test command, show output
- Before claiming a fix works: demonstrate the fix with evidence
- Before committing: verify build/lint/type-check pass
- Provide the actual command output as proof, not just assertions
- Before citing a green gate, show it saw **non-empty input**: print the count it
  processed, or make it fail once on purpose. Measured six times in one repo — a lint
  whose config ignored the whole report directory, an E2E suite green against a stale
  image, a planner that delivered 0 of 44 steps while its own linter said `OK`. Every
  gate was green and nobody was suspicious. When adding a gate, make it say how much it
  saw; and assert the tricky case at the **consumer's** seam, not only where it is known.
- Run a silent-on-failure check **bare**, never through a pipe. `manage.py migrate
  --check` prints nothing when migrations are pending — its whole verdict is the exit
  code, and a pipeline reports the last stage's status instead. Verified 2026-08-19: the
  same command gave `exit=0` piped and 1 bare, with a migration genuinely unapplied.
  Capture to a file and check `$?` before filtering.
- Prove a RED is genuine before you believe it: `git stash push -- <only the fix files>`,
  run the test, confirm it fails **for the right reason**, then pop. A security test can
  pass without the fix because the framework already rejected the case one layer down.
- For commands that can succeed partially (migrations, batch jobs, bulk imports, data backfills): exit code 0 is not enough. Verify counts/state before vs after, or check for skipped/failed records in logs. A "completed successfully" message that hides 14% skipped rows is a silent failure.
