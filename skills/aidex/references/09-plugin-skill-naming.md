# Plugin skill naming and visibility

aidex ships as a Claude Code plugin named `aidex`.

## Invocation form

- A plugin skill is invoked as `/<plugin>:<name>`, where `<name>` is the `name:`
  value in the skill's SKILL.md front-matter. For plugin skills that front-matter
  value overrides the folder name.
- aidex's skills therefore carry short names: `plan`, `audit`, `reference`, ... and the
  hub skill keeps `aidex`. Invocations read `/aidex:plan`, `/aidex:audit new`,
  `/aidex:aidex init`.
- Folder names are unchanged (`skills/aidex-plan/`, `skills/aidex/`, ...). A path
  such as `${CLAUDE_PLUGIN_ROOT}/skills/aidex-plan/scripts/x.sh` is a path, not an
  invocation, and keeps the folder spelling.

## skillOverrides does not apply to plugin skills

`skillOverrides` in `settings.json` / `settings.local.json` targets user- and
project-scope skills. Plugin skill visibility is managed through `/plugin`, not
through `skillOverrides`.

Consequence for the auditor: a `skillOverrides: name-only/off` patch can no longer
be emitted against aidex's own skills. It remains valid for non-plugin skills in a
user's ecosystem. Two sites in `skills/aidex/SKILL.md` (the token-savings code list
and the destructive-action checklist) still name `skillOverrides` as a toggle; they
are flagged in place and left for a later redesign.
