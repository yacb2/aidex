# Plugin skill naming and visibility

aidex ships as a Claude Code plugin named `aidex`.

## Invocation form

- A plugin skill is invoked as `/<plugin>:<folder>`, where `<folder>` is the skill's
  DIRECTORY name under `skills/`. The documentation says front-matter `name:`
  overrides it; **it does not** — measured at runtime on Claude Code 2.1.269 with a
  throwaway plugin, and corroborated by the eval trace `Skill(skill:
  "aidex-suite:aidex-artifact")`, which carried the folder spelling while `name:`
  was already short.
- Folders and `name:` are therefore both the short form and must agree:
  `skills/plan/` + `name: plan` → `/aidex:plan`, `skills/audit/` + `name: audit` →
  `/aidex:audit new`. The hub is the bare namespace root: `skills/aidex/` +
  `name: aidex` → `/aidex:aidex init`.
- No `aidex-` prefix on a directory: the `aidex:` plugin namespace already supplies
  it, and a prefixed folder would invoke as `/aidex:aidex-plan`.
  `test_registry_lockstep.py` guard 9 and `tests/test-plugin-layout.sh` check h both
  fail a directory that still carries one.
- A path such as `${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/x.sh` is a path, not an
  invocation, and uses the same folder spelling.

## skillOverrides does not apply to plugin skills

`skillOverrides` in `settings.json` / `settings.local.json` targets user- and
project-scope skills. Plugin skill visibility is managed through `/plugin`, not
through `skillOverrides`.

Consequence for the auditor: a `skillOverrides: name-only/off` patch can no longer
be emitted against aidex's own skills. It remains valid for non-plugin skills in a
user's ecosystem. Two sites in `skills/aidex/SKILL.md` (the token-savings code list
and the destructive-action checklist) still name `skillOverrides` as a toggle; they
are flagged in place and left for a later redesign.

## Two runtime gotchas measured at the 1.0.0 cut-over (2026-09-12)

- **A directory-source marketplace copies the whole directory into the cache,
  gitignored files included.** `claude plugin marketplace add <path>` +
  `claude plugin install` produced a 7.8 MB cache of which 364 KB was `_tmp/` and
  `plugin-evals/`. Harmless, but a local `_tmp/` holding backups or logs ships with
  the plugin. A GitHub source copies only the committed tree.
- **`claude plugin eval --case <glob>` matches the case.yaml `name:`, not the case
  folder.** Renaming folders alone leaves `--case` selecting zero cases;
  `tests/native-eval/collect-cases.sh` rewrites `name:` to `<skill>--<case>` for that
  reason, and the eval's results directory lives under the eval dir, so anything that
  rebuilds the eval dir destroys the previous report (`run-eval.sh` copies it out).
