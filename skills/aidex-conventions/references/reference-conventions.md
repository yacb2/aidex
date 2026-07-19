# Reference Module Conventions

Standards for creating numbered reference documentation modules (also covers `research/`).

> **Read [`00-global.md`](00-global.md) first.** Filename dates, language, cross-references, and minimum front-matter live there. This file only declares structure rules specific to references and research.

---

## Structure pattern

```
references/<topic>/
├── 00-index.md           # Master index
├── 01-<first-topic>.md
├── 02-<second-topic>.md
├── …
└── NN-<final-topic>.md
```

### No archive folder (D-05)

References and research are **versioned in place**. There is **no `_archive/`** in `references/` or `research/`. ADR: [`2026-05-14-archive-folder-convention.md`](../../../.context/decisions/2026-05-14-archive-folder-convention.md).

### Research shapes (ADR `decision/2026-07-02-research-artifact-shape`)

Research has **two sanctioned shapes**, size-based (mirroring the plan single-file vs modular threshold):

- **Single-document spike → flat dated file:** `research/YYYY-MM-DD-<slug>.md`. No folder overhead for a one-shot investigation.
- **Multi-document topic → dated topic folder:** `research/YYYY-MM-DD-<slug>/` with `00-index.md` (or the `00-overview.md` alias) + `NN-<slug>.md` files.
- **Promotion:** when a spike gains a second document, create the dated folder and move the spike in as its `00-index.md`.
- Legacy **undated** topic folders are grandfathered (renaming breaks inbound refs); new topics carry the date. `references/` keeps its undated `<topic>/` form — reference topics are evergreen by name, research is dated by nature.

When superseding content:

1. Update the existing module in place. Stamp `updated`.
2. If the old content has historical value, keep it in a clearly-labelled section (e.g., "### Legacy: pre-2026 setup") rather than relocating the file.
3. If a module is wholly replaced by another, add a top-of-file note linking forward and update inbound references.

```markdown
> **Note** This module replaces the legacy approach previously in `01-old-flow.md`.
```

---

## No README.md at root level

Do **NOT** create `README.md` inside `references/` or `docs/`. Each topic has its own `00-index.md`; `CLAUDE.md` is the top-level entry point linking to topics.

**Entry chain:** `CLAUDE.md` → `<topic>/00-index.md` → `<topic>/NN-<slug>.md`

---

## Accepted alias: `00-overview.md` in `research/`

The canonical master file name is `00-index.md`. The single accepted alias is `00-overview.md` **only inside `.context/research/<topic>/`**, where the semantics of "overview of an exploration" reads more naturally than "index of a finished module". Auditors report this alias as **INFO**, not WARNING.

In all other directories (`audits/` per [`audit-conventions.md`](audit-conventions.md), `decisions/`, `plans/`, `references/`, `docs/`, `roadmap/`), `00-index.md` is the only acceptable name and any other prefix-zero file is a WARNING.

---

## File naming

### Numbering

- **Two-digit prefix:** `00-` through `99-`
- **Index always `00-`:** `00-index.md` is the master entry point
- **Sequential:** no gaps (01, 02, 03 — not 01, 03, 05)
- **Separator:** single hyphen after number

### Name format

```
NN-<kebab-case-description>.md
```

Examples: `00-index.md`, `01-environment-setup.md`, `02-deployment-steps.md`, `11-troubleshooting.md`.

### Category prefixes (optional)

| Range | Category |
|---|---|
| 00 | Index |
| 01–09 | Core workflow / phases |
| 10–19 | Architecture / concepts |
| 20–29 | Operations / maintenance |
| 30+ | Reference / appendix |

Reference modules do **not** carry a date in the filename — only audits, backlog, plans, requests, and decisions do. Reference modules are evergreen and updated in place.

---

## `00-index.md` template

```markdown
---
title: "Topic name reference"
status: doing
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# [Topic Name] Reference

**Context:** [What this reference covers]

---

## Documents in this reference

| # | Document | Description |
|---|---|---|
| 00 | This index | Master reference and navigation |
| 01 | [First topic](./01-topic.md) | Brief description |
| 02 | [Second topic](./02-topic.md) | Brief description |

## Key information

[Critical information that applies to all modules — server URLs, credentials location, etc.]

## Related references

- [Related topic](../related/00-index.md)
```

`updated` is the freshness signal — stamp it on every edit; git-style change
logs are not tracked in `.context/` conventions. When a revision meaningfully
changes what the doc claims (not a typo pass), you MAY leave a one-line dated
note at the bottom — useful in projects whose `.context/` is gitignored, where
no VCS history backs the doc — but it is not mandated ceremony. `status` for references
typically stays `doing` (under active maintenance) or `done` (frozen, e.g.,
legacy system docs). `dropped` means superseded outright.

**Include when the topic needs them, not by default:** a `## Quick Reference`
action-to-document table (worth it for a large index with many entry points)
and a `## Prerequisites` list (worth it when the reader genuinely needs prior
setup). Omit both for a small or self-contained topic.

---

## Module template (`01-NN`)

```markdown
---
title: "Module title"
status: doing
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# [Module Title]

**Context:** [Module-specific context]

---

## Overview

[1–2 paragraphs — purpose, scope]

## Prerequisites

<!-- Include when the module needs prior setup; omit otherwise. -->

- [Prerequisite 1]
- [Prerequisite 2]

---

## [Main section]

### [Subsection]

\`\`\`bash
# Example command
command --flag value
\`\`\`

**Expected output:**

\`\`\`
Output here
\`\`\`

---

## Verification

- [ ] Check 1
- [ ] Check 2

## Troubleshooting

### [Issue]

**Symptom:** [What you see]
**Cause:** [Why it happens]
**Solution:**

\`\`\`bash
# Fix
\`\`\`

---

## Next steps

- [Next document](./NN-next.md)

## See also

- [Related document](./NN-related.md#section)
```

---

## Warning format

```markdown
> **Warning** Deploy CMS before frontend to avoid build failures.

> **Critical** Never run this command in production without backup.

> **Note** This step is optional for development environments.
```

---

## Cross-reference format

For links **inside the same reference module**, use relative file paths:

```markdown
[See setup steps](./01-setup.md#configuration)
[See related reference](../other-topic/00-index.md)
[Troubleshooting](./08-troubleshooting.md#database-connection-issues)
```

For cross-references to **other artifact types** (backlog, plans, decisions, etc.), use the `<type>/<filename>` form from [`00-global.md` §3](00-global.md#3-cross-references-d-03).

---

## Code block standards

- Always include a language hint (`bash`, `typescript`, `json`, `python`, …).
- Show expected output for commands when the output matters.

---

## Stable anchors — no bare line numbers

References are evergreen and outlive the code they describe, so anchor claims
with **stable references** (symbol names, "after the `speed_override` field",
file paths) — never bare line numbers, which go stale on the first intervening
commit. `file:line` is acceptable only as a supplement to a symbol anchor. No
consumer detects a rotted line anchor, so the discipline is on the author.

---

## Validation rules

`validate.py --type references` enforces exactly the following; everything else
in this file is authoring guidance, not a machine-checked rule:

- [ ] `00-index.md` (or `00-overview.md` in `research/`) exists for the topic
- [ ] File names match `NN-<kebab-case>.md` (kebab-case, two-digit prefix)
- [ ] No `_archive/` folder (D-05)
- [ ] The index (and any non-sub-document file) carries `title`, `created`,
      `updated`; `status` is optional (references are documentation, not work
      items). Module sub-documents (`NN-*.md` under a topic) are exempt from
      front-matter entirely.
- [ ] Dates use `YYYY-MM-DD` (D-01)
- [ ] Cross-references resolve to an existing artifact
- [ ] Body is written in English (D-04)

Not enforced (author judgment): sequential numbering, section presence
(Overview / Quick Reference / Prerequisites / Documents table), and anchor-link
integrity. `version` front-matter and a Version-history section are **not**
mandated — `updated` is the freshness signal.

---

## Related

- [`00-global.md`](00-global.md) — shared rules.
- [`claudemd-conventions.md`](claudemd-conventions.md) — how CLAUDE.md links to references.
