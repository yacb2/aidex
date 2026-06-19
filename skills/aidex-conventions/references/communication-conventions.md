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
├── received/           # async inbound  (email, whatsapp)
│   └── <YYYY-MM-DD>-<slug>/
│       ├── body.md
│       └── <attachment files alongside>
├── sent/               # async outbound (email, whatsapp) — draft → sent
│   └── <YYYY-MM-DD>-<slug>/
│       └── body.md
├── meetings/           # synchronous, multi-party (meeting + call) — no direction
│   └── <YYYY-MM-DD>-<slug>/
│       ├── body.md
│       └── <transcript / recording link / slides>
└── _archive/           # optional (D-05); move old terminal entries here
```

- Each communication is a **folder**, not a single file — so attachments (PDFs,
  images, the original `.eml`, a transcript) sit alongside `body.md`.
- **Date:** `YYYY-MM-DD` per D-01 — the date of the communication (received, drafted, or held).
- **Slug:** kebab-case, 3–6 words. Describes the *topic*, not the channel or status.

### Async vs. synchronous — the primary axis

The taxonomy splits first on **how the communication happened**, not on direction:

- **Asynchronous correspondence** — a message authored at one time and read at another. It
  has a **direction** (it was *received* from someone, or *sent* to someone): email,
  WhatsApp, letters. These live in `received/` and `sent/`.
- **Synchronous conversation** — a real-time, multi-party exchange. It has no direction; it
  has **participants**. A meeting or a call is not "received from" or "sent to" anyone — two
  or more people were in the room. These live in `meetings/`.

Filing a meeting under `received/`/`sent/` is a distortion (it forces a sender→receiver pair
onto something that has neither). Use `meetings/` for any `meeting` or `call`.

### Received vs. sent (async only)

| Split | Meaning | Initial `status` |
|---|---|---|
| `received/` | A message that arrived from someone else. A record. | `sent` (it already happened) |
| `sent/` | A message we are composing to send out. | `draft` |

The split is by **direction of the message**, not by who initiated the thread. A reply
we write to an inbound email still goes under `sent/`.

### Meetings & calls (synchronous)

Both `meeting` and `call` live in `meetings/` — one folder for real-time conversations,
with `channel` disambiguating modality (a 1:1 phone call is `channel: call`; a multi-attendee
video meeting is `channel: meeting`). A synchronous record is always created with
`status: sent` — it already happened.

---

## Front-matter

### Async (`received/`, `sent/`)

```yaml
---
channel: email          # email | whatsapp | other
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

- `channel` — one of `email | whatsapp | other`.
- `direction` — `received | sent`; mirrors the folder it lives in.
- `from` / `to` — free text; whatever identifies the parties.
- `subject` — the subject line, or a short topic for channels without one.
- `status` — `draft` while composing an outgoing message, `sent` once it has gone out (or
  for any received record, which is `sent` from the start).
- `related` — D-03 cross-references to other `.context/` artifacts (the request it spawned,
  the decision it informed). Defaults to `[]`.

### Synchronous (`meetings/`)

```yaml
---
channel: meeting        # meeting | call
participants:           # replaces from/to — the people in the conversation
  - "Yoel Acevedo <yoel@nonstop.dev> (NonStop)"
  - "Gustavo Cornillon <gustavo@mediaaccess.com> (Media Access)"
organizer: "Yoel Acevedo"   # optional — who convened it
subject: "DubApp ↔ Access Core kickoff"
date: 2026-06-10
status: sent            # a meeting/call already happened
related: []             # D-03 cross-refs (the request/decision it spawned)
created: 2026-06-10
updated: 2026-06-10
---
```

- `channel` — `meeting | call`. Describes modality; the `meetings/` folder carries the
  "synchronous" meaning.
- `participants` — a list, replacing `from`/`to`. There is **no `direction`** key.
- `organizer` — optional; who called the meeting.
- `subject`, `status` (always `sent`), `related` — as above.

### Body

The body is free-form prose. For async, the message text or summary. For a meeting/call,
notes organized however fits — a common shape is **Agenda · Notes · Decisions · Action
items**.

---

## Draft → sent flow

1. Scaffold an outgoing message under `sent/` with `status: draft`.
2. Iterate on the body until it is ready.
3. When it actually goes out, set `status: sent` and bump `updated`.

A `received/` entry skips this flow: it is a record of something that already arrived, so
it is created with `status: sent`. The draft→sent flow is **exclusive to outgoing async
messages** — a `meetings/` entry already happened, so it is created with `status: sent` too.

### Worked examples by case type

- **Client video meeting**, multiple attendees, with a Gemini/Otter transcript attached →
  `meetings/<date>-<slug>/` with `channel: meeting`, every attendee in `participants`,
  the transcript dropped alongside `body.md`.
- **Internal team standup or design call** → `meetings/` with `channel: meeting` (or `call`
  if voice-only), the team in `participants`.
- **1:1 phone call with a supplier** → `meetings/` with `channel: call`, two `participants`.
- **A meeting that spawns a request or decision** → log the meeting in `meetings/`, capture
  the requirement in `requests/` (or the ADR in `decisions/`), and cross-link via `related`.
- **An inbound client email** → `received/` with `channel: email`, `from`/`to`, `status: sent`.

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

## Relocating a meeting filed under `received/` or `sent/`

Before `meetings/` existed, a meeting or call could only be filed under `received/`/`sent/`
as a workaround — with `from`/`to` standing in for attendees, implying a direction the
conversation never had. The canonical "before" example is the 2026-06-10 DubApp ↔ Access
Core meeting in `echo_lab_ws`, filed under `received/` with `from` = the other company.

To relocate such an entry:

1. Move the folder to `meetings/` (keep the `<date>-<slug>` name and attachments).
2. Rewrite the front-matter to the synchronous schema: drop `direction`, replace `from`/`to`
   with a `participants` list, keep `channel: meeting|call`, set `status: sent`.

Like the `drafts/` rename, this is **manual and opt-in** — auditors flag a `meeting`/`call`
entry living under `received/`/`sent/` as an INFO-level relocation suggestion, never an
automatic move. Existing async `received/`/`sent/` entries are unaffected.
