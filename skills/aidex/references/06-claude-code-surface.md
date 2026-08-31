# Claude Code surface — what the auditor's recommendations assume

The ecosystem auditor tells people to change their configuration. Every one of those
recommendations rests on a fact about Claude Code that can stop being true in a release,
and when it does the recommendation does not become an error — it becomes *confidently
wrong advice*, which is worse. That happened once already: aidex caught up with
`skillOverrides` and MCP scoping by hand on 2026-05-06/07 (`fa1f2c6`), **after** the auditor
had recommended removing plugins that were fine.

Nothing made that drift visible, because nowhere recorded which Claude Code the advice was
checked against. This file is that record. `scripts/surface-drift-check.py` reads the table
below, compares it against the installed `claude --version`, and reports which rows need
re-verifying.

**It reports, never prescribes.** A newer Claude Code does not mean a recommendation is
wrong — it means nobody has looked. The check says "re-verify this"; a human decides what,
if anything, changes.

## Surfaces

Each row: the surface, the Claude Code version its behaviour was last verified against, and
the auditor recommendation that would be wrong if it changed. The version column is parsed —
keep it a bare `MAJOR.MINOR.PATCH`.

| Surface | Verified against | Recommendation that depends on it |
|---|---|---|
| skillOverrides values | 2.1.241 | The auditor emits `name-only`, `user-invocable-only` or `off` into a project's `.claude/settings.local.json`. A fourth value, a renamed key, or a changed default would make every emitted patch either inert or wrong. |
| skillOverrides key namespacing | 2.1.241 | A plugin's skill registers under `<plugin>:<skill>` (`document-skills:docx`), a personal skill under its bare directory name. An override key written in the wrong form matches nothing: it is valid JSON naming a real skill, so nothing reports it, and the skill loads at full cost while the settings file says it does not. Checked by `scripts/check-skill-overrides.py`. If namespacing changes, every emitted patch silently stops applying. |
| skillOverrides cost model | 2.1.241 | The advice "prefer `off` over `name-only` when the stack excludes a skill" rests on `user-invocable-only` costing the same as `off` (134 tok/skill, measured). If loading changes, the ranking changes with it. |
| MCP scoping | 2.1.241 | The auditor reasons about project-scope vs user-scope MCP servers when attributing idle context cost. A change in where servers are declared or when they connect moves that attribution. |
| Plugin handling | 2.1.241 | Uninstall candidates are proposed from `~/.claude/plugins/installed_plugins.json` and always-loaded subagent cost. This is the one that has already misfired — plugins were recommended for removal that were fine. |
| Settings file precedence | 2.1.241 | Patches are written to `.claude/settings.local.json` on the assumption it overrides `settings.json` and stays out of version control. If precedence or the recommended file changes, patches land somewhere that does not win. |

## Checking the override keys themselves

`scripts/check-skill-overrides.py` reads `~/.claude/settings.json` and reports every
`skillOverrides` key that resolves to nothing, with the namespaced id it probably meant.
Read-only; exit 1 on any unresolved key, 2 on a settings file it cannot read.

Pass `--skills-dir <store>` for each personal skill store that is installed **per
project** — a `.claude/skills/<name>` symlink pointing at something like
`~/.myskills/skills/`. Without it those keys read as unresolved, which is the false
positive that makes a checker like this one get discounted. On this machine:

```
python3 ~/.claude/skills/aidex/scripts/check-skill-overrides.py --skills-dir ~/.myskills/skills
```

It also reports **SHADOWED**: a bare key that does resolve to a personal skill while a
namespaced twin of the same name exists and keeps loading unoverridden. That is not a
failure — the key is valid — but it silences half of what the reader thinks it silences.

## Re-verifying a row

1. Check the current behaviour against the official docs or a live probe — for anything
   about Claude Code, the API, or the Agent SDK, the `claude-code-guide` agent is the source
   to ask, not memory.
2. If the behaviour is unchanged, bump only the version column to the version you checked
   against. That is the normal outcome and it is the whole point: it converts "nobody has
   looked" into "checked on this version".
3. If it changed, fix the recommendation at its source first — the auditor's SKILL.md, an
   agent prompt, a script — then bump the row.
4. Note anything surprising in the row's third column. A row that keeps changing is telling
   you the recommendation is built on something unstable.

## What does NOT belong here

Facts that are not load-bearing for a recommendation. The temptation is to make this a
changelog of Claude Code, which would go stale the moment nobody is paid to maintain it. A
row earns its place only when a specific piece of advice would be wrong without it — which
is why the third column is required, not decorative.
