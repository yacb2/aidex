# Launch sequence — v1.0.0

What is NOT done by the run: nothing in this file is executed by the migration run.
Push, release and posts are the owner's.

1. Merge `plugin-migration` into `main`.
   Gate: phase 5 cut-over signed off by the owner on their machine; `bash tests/run-all.sh` green; `claude plugin validate .` exit 0.
2. Owner: `git push origin main --tags`, `gh release create v1.0.0 --notes-file docs/releases/v1.0.0.md`.
   Gate: local tag `v1.0.0` exists on the merge commit; first Release since v0.30.0.
3. GIF of `/aidex:artifact` turning a discussion into a consultation page.
   Gate: the plugin is installed live, step 1; script: one Spanish prompt, the page opening locally, the ledger; under 30 seconds.
4. Base post text, then Reddit r/ClaudeAI, then Show HN, then the long-form write-up, then the Spanish article, then the awesome-list PR last.
   Gate for each: the previous one is published and the install command in it was re-tested from a clean machine.
5. Out of this repo: the claude-restart claim from the visibility plan (item D1) is owed elsewhere; note it as owed, do not describe it.
