# Verification Before Completion Claims

## NEVER

- Claim "tests pass", "build succeeds", or "bug is fixed" without running the verification command and showing output
- Trust cached or remembered results — always run fresh
- Say "should work", "looks correct", or express satisfaction without evidence

## ALWAYS

- Before claiming tests pass: execute the test command, show output
- Before claiming a fix works: demonstrate the fix with evidence
- Before committing: verify build/lint/type-check pass
- Provide the actual command output as proof, not just assertions
- For commands that can succeed partially (migrations, batch jobs, bulk imports, data backfills): exit code 0 is not enough. Verify counts/state before vs after, or check for skipped/failed records in logs. A "completed successfully" message that hides 14% skipped rows is a silent failure.
