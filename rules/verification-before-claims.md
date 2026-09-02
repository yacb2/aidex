# Verification Before Completion Claims

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
