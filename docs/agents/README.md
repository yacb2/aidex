# Routed agents

The subagents the main session routes work to by description ship in `agents/` and are
launched as `aidex:<name>`: `bugfix-opus`, `review-diff-opus`, `smoke-sonnet`,
`synthesis-sonnet`, `task-general`, `verify-browser-opus`, `verify-browser-sonnet` (more are
added there as they are ported). Each states in its description when to use it; skill-launched
agents say "Launched by /aidex:X; not for direct use" instead.

- `smoke-sonnet` and `verify-browser-*` need the chrome-devtools MCP server, which the plugin
  does not ship. Without it they start with Bash and Read only and say so.
- To opt out of one agent, add a `deny` permission rule `Agent(<name>)` (for example
  `Agent(aidex:verify-browser-opus)`).
- An agent that preloads skills through `skills:` front matter fails silently if a skill is
  not installed, so `tests/test-staged-agents-preload.sh` fails on any entry that names a
  skill `skills/` does not ship.
