# UI contract — <project> (`.context/profiles/ui-contract.md`)

Read this instead of the testing profile and the harness contract. It is the project's
standing answer to "how do galleries work here"; a screen's own `gallery-kit.md` adds only
that screen's spec, cells and last run. Created at the first gallery build on the project
(fill the sections from the harness contract and the first working spec); every round's
agent appends the pitfalls it hit, with file:line, before it hands back.

## Capture

- Modes and widths: <e.g. light, desktop only, 1600x900; dark and mobile only when the owner asks>.
- Harness: `<path to the harness module>`. Exports: <the helpers a spec calls, e.g. open cell,
  screenshot check, overflow, layout-settled, contrast, mock helpers, the per-cell drive type>.
  Call order per cell: <open -> full-content step -> screenshot -> overflow -> layout -> contrast>.
- Pattern spec to copy: `<path>` (<one line on its shape>).
- Commands, from the worktree root. The spec path goes BEFORE every flag:
  - capture (the one run of a round): `<runner> <spec> --no-deps --update-snapshots`
  - only some cells: append `--grep "<regex>"`; anchor short names (`"gallery error$"`).
  - gate (close only): `<runner with the meta-suite>`
- One capture run per round. The confirmation run (no update) is the hardening gate.
- Rows JSON: a row whose visible change the owner did not ask for (shared i18n key or
  component, layout knock-on) is `kind: "unrequested"` with a `look` line naming the cause ([rows](${CLAUDE_PLUGIN_ROOT}/skills/artifact/references/04-block-vocabulary.md#gallery--scriptsdashgallery_itemspy-rows-json-in)).
- Rows JSON: a changed full-page row (capture 320x600 or larger) needs `"highlight": "@name"`
  and the capture's `<capture>.regions.json`; the build refuses it otherwise (BL-688).
- A dropped cell's baseline is not deleted by `--update-snapshots`: copy it aside, then `rm` it.

## Pitfalls already paid for (do not rediscover)

Each entry: the symptom, the cause with `file:line`, the fix. Append new ones; keep old ones.

1. <symptom -> cause (`path:line`) -> fix>

## Visual system

- <the components a screen is built from, the strings or states with no shared component yet>

## Decided UI patterns

- <pattern, date, source consultation>
