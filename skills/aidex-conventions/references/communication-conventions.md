# Communication Conventions

Standards for logging real correspondence and drafting outgoing messages in
`.context/communications/`.

> **Read [`00-global.md`](00-global.md) first.** Filename dates, archive, cross-references, and minimum front-matter live there. This file only declares what is specific to communications — including the one place they deliberately diverge from the global rules: **language**.

---

## Purpose

A communication is a record of real correspondence with a person — an email,
WhatsApp message, phone call, or meeting — or the draft of an outgoing message before
it is sent. It is the durable log of *what was actually said*, not a derived artifact.

This is distinct from a **request** (`.context/requests/`): a request captures the
*requirement to act on* (the ask), in English, as a knowledge artifact. The
communication captures the *raw message itself*, in its original language. Log the
client's email here; capture the requirement it contains there, and cross-link them via
`related`.

---

## Location & naming

```
.context/communications/
├── received/
│   └── <YYYY-MM-DD>-<slug>/
│       ├── body.md
│       └── <attachment files alongside>
├── sent/
│   └── <YYYY-MM-DD>-<slug>/
│       └── body.md
└── _archive/            # optional (D-05); move old terminal entries here
```

- Each communication is a **folder**, not a single file — so attachments (PDFs,
  images, the original `.eml`) sit alongside `body.md`.
- **Date:** `YYYY-MM-DD` per D-01 — the date of the communication (received or drafted).
- **Slug:** kebab-case, 3–6 words. Describes the *topic*, not the channel or status.

### Received vs. sent

| Split | Meaning | Initial `status` |
|---|---|---|
| `received/` | A message that arrived from someone else. A record. | `sent` (it already happened) |
| `sent/` | A message we are composing to send out. | `draft` |

The split is by **direction of the message**, not by who initiated the thread. A reply
we write to an inbound email still goes under `sent/`.

---

## Front-matter

```yaml
---
channel: email          # email | whatsapp | call | meeting | other
direction: received     # received | sent  (must match the parent folder)
from: "Ana López <ana@cliente.com>"
to: "Equipo Ventas"
subject: "Cotización catálogo primavera"
date: 2026-06-17
status: sent            # draft | sent
related: []             # D-03 cross-refs (e.g. requests/2026-06-17-spring-pricing.md)
created: 2026-06-17
updated: 2026-06-17
---
```

- `channel` — one of `email | whatsapp | call | meeting | other`.
- `direction` — `received | sent`; mirrors the folder it lives in.
- `from` / `to` — free text; whatever identifies the parties.
- `subject` — the subject line, or a short topic for channels without one.
- `status` — `draft` while composing an outgoing message, `sent` once it has gone out (or
  for any received record, which is `sent` from the start).
- `related` — D-03 cross-references to other `.context/` artifacts (the request it spawned,
  the decision it informed). Defaults to `[]`.

### Body

The body is free-form prose: the message text, call summary, or meeting notes.

---

## Draft → sent flow

1. Scaffold an outgoing message under `sent/` with `status: draft`.
2. Iterate on the body until it is ready.
3. When it actually goes out, set `status: sent` and bump `updated`.

A `received/` entry skips this flow: it is a record of something that already arrived, so
it is created with `status: sent`.

---

## Language — English-only EXEMPTION

Communications are **exempt** from the D-11 English-only rule that governs knowledge
artifacts (plans, decisions, requests, research, references, docs, audits, backlog, loops,
CLAUDE.md, skill prose). A communication is a faithful record of what was actually said, so
the body is kept in the **native language of the communication** — a Spanish client email
stays in Spanish, a French supplier WhatsApp stays in French.

This exemption is scoped to the **body and the human-facing front-matter values**
(`from`, `to`, `subject`). The front-matter **keys** stay as defined above. Note that this
is the only `.context/` type with such an exemption — everywhere else, English always.

---

## Migrating from `drafts/`

Some projects already keep this log by hand under a legacy `drafts/` folder:

```
.context/drafts/received/<date>-<slug>/body.md
.context/drafts/sent/<date>-<slug>/body.md
```

This maps **1:1** to the canonical layout — `drafts/` is just the old name for
`communications/`. The schema, the received/sent split, and the front-matter are
identical.

**The rename is manual and opt-in. Do NOT auto-migrate user projects.** These entries
live in workspace-private, untracked `.context/`, and renaming a folder that someone
relies on by hand is the kind of surprise a tool should not spring. If a user explicitly
asks to migrate, the one-liner is:

```bash
# from the project root, with .context/drafts/ present
git mv .context/drafts .context/communications 2>/dev/null \
  || mv .context/drafts .context/communications
```

(`git mv` only applies if `.context/` is tracked, which it usually is not.) Aidex auditors
should treat a legacy `drafts/` directory as an INFO-level note suggesting the rename — not
a WARNING, and never an automatic move.
