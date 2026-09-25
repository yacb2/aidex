# Staged personal agents

These are the owner's personal subagent definitions (`impl-opus`, `bugfix-opus`,
`review-diff-opus`), staged here so the testing-canon eval can load them with `--agents`
and so their change is reviewable. They are not installed by `install.sh` or the plugin:
agents stay personal, and the merge copies these files to `~/.claude/agents/` by hand.

Each preloads skills through its `skills:` front-matter. A preloaded skill that is not
installed is skipped silently, so `tests/test-staged-agents-preload.sh` fails on any entry
that names a skill `skills/` does not ship.
