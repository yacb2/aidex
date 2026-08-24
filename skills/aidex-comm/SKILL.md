---
name: aidex-comm
description: 'Use when the user wants to log or draft a real communication with a person — capture an email/WhatsApp that was received, log a meeting or call that happened, or draft a message/email to send — as a written `.context/communications/` entry, kept in the communication''s native language. Fires on "log this email", "save the email the client sent", "capture this WhatsApp from X", "record the call with X", "log the meeting with X", "draft an email to X", "write a reply to the client", "save this thread", and /aidex-comm commands. Not for: capturing a stakeholder/product requirement to act on (aidex-request); recording a decision/ADR (aidex-decision); planning multi-step work (aidex-plan); deferring an idea (aidex-backlog); research notes (aidex-research); references (aidex-reference); ecosystem audits (aidex); project-state audits (aidex-audit).'
argument-hint: "[new <received|sent|meeting|call> <slug> [--channel email] | migrate]"
disable-model-invocation: false
allowed-tools: Bash Read Write
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-comm"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Communications

Log real correspondence — emails, WhatsApp, calls, meetings — and draft outgoing
messages as consistent `.context/communications/` entries. Each entry is a folder
holding a `body.md` (plus any attachments alongside it). The taxonomy splits on
**async vs synchronous**: async correspondence has a direction (`received/`, `sent/`);
synchronous conversations — meetings and calls — have participants, not a direction, and
live in `meetings/`. Communications are kept **in their native language** (D-04
English-default does NOT apply here; D-11 governs skill *descriptions*, not artifact bodies).

---

## Sub-actions

| Command | Script | Purpose |
|---|---|---|
| `/aidex-comm new received <slug> [--channel email]` | [scripts/new-communication.sh](scripts/new-communication.sh) | Scaffold a received async record (email/WhatsApp) under `received/` |
| `/aidex-comm new sent <slug> [--channel whatsapp]` | same | Scaffold an outgoing async draft under `sent/` (status starts `draft`) |
| `/aidex-comm new meeting <slug>` | same | Scaffold a synchronous meeting record under `meetings/` (participant-based, `status: sent`) |
| `/aidex-comm new call <slug>` | same | Scaffold a synchronous call record under `meetings/` (participant-based, `status: sent`) |
| `/aidex-comm migrate` | [scripts/migrate-communications.sh](scripts/migrate-communications.sh) | Rename pre-canonical `email.md` / `conversation.md` bodies to `body.md`, reporting each |

`--channel` is async-only and accepts `email` (default), `whatsapp`, `other`. For meetings
and calls use `new meeting` / `new call` — the channel is fixed to the kind.

---

## Dispatch

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/new-communication.sh" "$@"
```

For `migrate`:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/migrate-communications.sh"
```

It renames only files sitting directly inside a `<YYYY-MM-DD>-<slug>/` entry folder, never
attachments, and refuses any rename that would clobber an existing `body.md` (exit 1). Run
`validate.py --type communications` first if you want the preview — the
`communication-legacy-body-name` findings are exactly what it will rename.

The script scaffolds `.context/communications/<received|sent|meetings>/<YYYY-MM-DD>-<slug>/body.md`
from the matching template, refuses to overwrite, and prints the created path on stdout.
For async, fill `from`/`to`/`subject`; for meetings/calls, fill `participants`/`subject`.
Write the body afterward in the native language.

---

## Entry format

**Read `~/.claude/skills/aidex-conventions/references/communication-conventions.md`
before writing an entry** — it is the full canon behind the shapes below: the
front-matter schema per direction, async (`received`/`sent`) vs synchronous
(`meetings/`), the draft→sent transition, the English-only exemption for bodies, and
how to migrate a legacy `drafts/` folder.

```
.context/communications/
  received/<YYYY-MM-DD>-<slug>/body.md   (+ attachments alongside)   async inbound
  sent/<YYYY-MM-DD>-<slug>/body.md                                   async outbound
  meetings/<YYYY-MM-DD>-<slug>/body.md   (+ transcript/slides)       synchronous (meeting + call)
```

**Async** (`received/`, `sent/`) front-matter — directional, `from`/`to`:

```markdown
---
channel: email          # email | whatsapp | other
direction: received     # received | sent
from: "..."
to: "..."
subject: "..."
date: YYYY-MM-DD
status: sent            # draft | sent  (received records are 'sent'; outgoing start 'draft')
related: []             # D-03 cross-refs to other .context/ artifacts
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

<body — in the NATIVE language of the communication>
```

**Synchronous** (`meetings/`) front-matter — non-directional, `participants` instead of
`from`/`to`, always `status: sent` (it already happened):

```markdown
---
channel: meeting        # meeting | call
participants:           # the people in the conversation
  - "Yoel Acevedo <...> (NonStop)"
  - "..."
organizer: "..."        # optional
subject: "..."
date: YYYY-MM-DD
status: sent
related: []
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

<agenda / notes / decisions / action items — in the NATIVE language>
```

---

## After a meeting: action items become tracked work

Logging the meeting is half the job. A meeting record whose action items stay inside
`body.md` is a note, not a commitment — the hop to a tracker was manual and unnamed, so it
did not happen. **Once the body is written, walk its action items and derive each one**:

| The action item is… | Register it as | Command |
|---|---|---|
| Work this side has agreed to do | a backlog entry | `bash ~/.claude/skills/aidex-backlog/scripts/register-item.sh --origin communication --communication <folder> --title "<item>"` |
| Something a stakeholder or client is asking for | a request | `/aidex-request` — capture the ask, then cross-ref the communication |
| A decision the meeting settled | an ADR | `/aidex-decision` |

`--origin communication` stamps `origin_ref: communication/<YYYY-MM-DD>-<slug>` — the D-03
marker, the folder name, never a filesystem path. That is what makes the entry answer
"where did this come from?" six months later.

**Derive, do not transcribe.** An action item is a line in someone's notes; a backlog entry
needs a title that stands alone. "Ver lo del export" becomes "Add CSV export to the bookings
list". Say what you registered when you are done, so nothing is created silently.

If the meeting produced no action items, say so and stop — an empty derivation is a valid
outcome and inventing work to fill the step is worse than skipping it.

---

## Drafting: read what was actually sent before opening the template

For the `sent/` path, **read the existing entries in `.context/communications/sent/` of the
same channel before you draft** — the folder is a corpus of messages this project really
sent, and it is the only record of how it sounds. Match structure (how it opens, how much
context it restates, how it closes) and register (formal vs direct, how requests are
phrased). Prefer the most recent few and any addressed to the same interlocutor.

The template is the fallback, not the starting point: use it when `sent/` is empty or holds
nothing of the same kind. Say which prior entries you leaned on.

**Never translate to match a sample.** D-04 keeps every body in the communication's own
language; a Spanish thread stays Spanish even when the closest structural example is
English. Borrow the shape, never the language.

### The house style is already in the scaffolded body

`new-communication.sh` reads `.context/communication-style.md` and renders its five axes —
voice, sign-off, tone, address, date format — into the `body.md` it creates, so the draft
starts in this workspace's voice instead of being corrected into it. A workspace with no
profile gets the documented defaults; that is the normal case, not an error. Read the block
at the top of the scaffolded file before writing, and if a correction keeps recurring on a
sixth axis, record it in the profile rather than re-applying it. Full shape:
`aidex-conventions/references/communication-conventions.md` § House style.

### An outgoing email body must survive a paste into Outlook or Gmail

Neither client renders markdown, and the body is going to be pasted into one of them. Two
constructs have already reached real recipients broken — a table as a literal `|` grid, a
blockquote as literal `>` characters. So in a `sent/` entry with `channel: email`:

| Do not write | Write instead |
|---|---|
| a markdown table | a bulleted list, or short `Label — value` lines |
| a markdown blockquote (`> …`) | plain prose, or `Ana escribió:` followed by the text |

Bold, links and bullets paste correctly, so they stay available. `validate.py` enforces
this as `communication-paste-unsafe` — scoped to `sent/` + `channel: email` only. A
`received/` body is a faithful capture of what arrived: a table there is *correct*, and
`>`-quoted thread text is the normal inbound shape, so neither is flagged.

If the recipient genuinely needs a rendered table, write a `body.html` **alongside**
`body.md` and have the user paste that one — attachments already live next to the body,
so this needs no new file tier. It is opt-in: do not emit one unless it is asked for.

---

## Draft → sent flow

An outgoing message is scaffolded under `sent/` with `status: draft`. When it actually
goes out, set `status: sent` and bump `updated`. A received communication is a record of
what already arrived, so it lands with `status: sent` from the start. The draft→sent flow
is exclusive to outgoing async messages: meetings and calls already happened, so they land
with `status: sent` too.

---

## Self-check (mandatory close step)

Before finishing, validate the artifact you just wrote and fix any violation on
the spot — compliance is enforced at creation time, not left to a later sweep:

```bash
python3 ~/.claude/skills/aidex-conventions/scripts/validate.py --type communications
```

If the project carries a ratchet baseline (`.context/.validate-baseline.json`),
a non-zero exit means you introduced a NEW violation — fix it before closing.

## Related

- **aidex-request** — for a stakeholder/product *requirement* to act on (the ask), not the raw message; log the message here, capture the requirement there.
- **aidex-conventions** — parent convention for `.context/communications/`.
