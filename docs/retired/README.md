# Retired: the pre-plugin installer

This folder holds what the plugin migration retired: `install.sh` (with its
`--update`, `--doctor` and `--uninstall` modes and the `~/.claude/aidex/` manifest it
maintained), its two tests `tests/test-install.sh` and `tests/test-doctor.sh`, and the
`rules/` folder that used to be copied into `~/.claude/rules/`. Since v1.0.0
(2026-09-12) aidex ships as a Claude Code plugin: skills, agents and hooks are loaded
from the plugin itself, so copying files into `~/.claude/` has no job left, and a
plugin cannot ship always-on rules at all — each retired rule's canon lives on in the
`conventions` skill's `references/`, cited by the skills that need it. To roll back to
a pre-plugin setup, check out the last pre-plugin tag and run the installer from there
(`git checkout v0.55.0 && ./install.sh`); running `bash docs/retired/install.sh` from
this tree does not work, because the script resolves `skills/` and `rules/` relative to
its own directory. The install diagnosis that `--doctor` provided returns as a skill
sub-action under backlog item BL-404.

`agents/` holds the `durability-arbiter` agent and its eval, retired 2026-10-05: it was
launched 0 times in 30 days while the five skills that consulted it ran 160+ times. Its
policy lives on as the canonical ARBITER block in
`skills/conventions/references/workflow-core.md`, which the running session applies itself.

`hooks/` holds the retired `aidex-router.sh` (UserPromptSubmit prompt router, with its `eval/`
harness) and the durability Stop hook (`durability-stop-hook.sh`, `durability-run.sh`,
`durability-stop-prompt.md`, `test-durability-hook.sh`), moved out of the shipped `hooks/`
folder on 2026-10-17. Both were unwired since 2026-08-03 (the durability hook's sunset criterion
fired; the router's replay came out p=0.72), and the suite no longer runs their tests. Their
README, with the sunset criterion, is `hooks/README.md` here. Re-wiring means copying the files
back into `hooks/` and adding a `hooks.json` entry, after a new falsifiable criterion.

`scripts/build-memory-worklist.py` and `tests/test-memory-worklist.sh`: a one-shot tool for the
2026-08-31 fleet memory cleanup (all 49 executions happened that day), retired 2026-10-17. No
skill, reference or agent names it.

`agents/bug-investigator.md`, `test-scout.md` and `regression-checker.md`: the bugfix helper
agents, retired 2026-10-17. None was ever launched by type; `aidex:bugfix-opus` runs steps 1-6
itself and now carries the sibling-sweep and bounded-RED clauses.

`skills/plan-exec/assets/workflows/review-with-gate.workflow.js` was deleted on 2026-10-17
(0 launches in 60 days). A terminal clean-context review is an `agent()` call inside
pipeline-with-gate (`workflow-core.md`, "Reviewer is blind"); the file is in git history.
