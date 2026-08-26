# `.context/` — worked example (fictional project: room-booking)

A small Django + Vue app's working memory, laid out exactly as the aidex
conventions expect. Every file is short on purpose: the point is the shape.

| Folder | What lives there |
|---|---|
| `backlog/` | Work items, one file each (`YYYY-MM-DD-bl-nnn-<slug>.md`); `00-index.md` is generated, `_archive/` holds closed items |
| `plans/` | Implementation plans; a modular plan is a folder with `00-index.md` + phase files; `plans/00-index.md` is the generated roll-up |
| `decisions/` | ADRs (`accepted` / `superseded` / `dropped`); superseded ones move to `_archive/` and point forward via `superseded_by` |
| `research/` | Spikes and investigations, versioned in place (no archive) |
| `references/` | Evergreen how-it-works docs, one `<topic>/` folder with `00-index.md` + `NN-*.md` |
| `requests/` | Stakeholder asks, tracked until escalated to a backlog item or plan |
| `audits/` | One folder per methodology (`00-methodology.md`, `00-inventory.md`, `00-changelog.md`) plus dated run folders |
| `communications/` | Not shown: real emails/meetings, kept in their native language and never sanitised |

Front-matter minimum on every artifact: `title`, `status`, `created`, `updated`
(ISO dates). Cross-references are `<type>/<filename>` — `decision/2026-07-20-…`,
`backlog/2026-08-26-bl-002-…` — and keep resolving after a move to `_archive/`.

## Three commands

```bash
# Validate the tree (0 violations expected; run from the repo root)
python3 skills/aidex-conventions/scripts/validate.py examples/.context
# ...or, once aidex is installed:
python3 ~/.aidex/skills/aidex-conventions/scripts/validate.py examples/.context

# Render the backlog board to a self-contained HTML page (from inside examples/)
~/.aidex/skills/aidex-dash/scripts/render.sh backlog

# Register a backlog item (from inside examples/; the id and 00-index.md are generated)
~/.aidex/skills/aidex-backlog/scripts/register-item.sh --origin manual --title "Add room photos" --priority P2
```

Scripts find the nearest `.context/` above the working directory, so run the
last two from `examples/` to act on this tree rather than on your own project.
