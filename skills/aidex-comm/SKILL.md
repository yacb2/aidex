---
name: aidex-comm
description: Use when the user wants to log or draft a real communication with a person — capture an email/WhatsApp/call/meeting that was received, or draft a message/email to send — as a written `.context/communications/` entry, kept in the communication's native language. Fires on "log this email", "save the email the client sent", "capture this WhatsApp from X", "record the call with X", "draft an email to X", "write a reply to the client", "log the message we got", "save this thread", and /aidex-comm commands. Not for: capturing a stakeholder/product requirement to act on (aidex-request); recording a decision/ADR (aidex-decision); planning multi-step work (aidex-plan); deferring an idea (aidex-backlog); research notes (aidex-research); references (aidex-reference); ecosystem audits (aidex); project-state audits (aidex-audit).
argument-hint: "[new <received|sent> <slug> [--channel email]]"
disable-model-invocation: false
allowed-tools: Bash Read Write
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-comm"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Communications

Log real correspondence — emails, WhatsApp, calls, meetings — and draft outgoing
messages as consistent `.context/communications/` entries. Each entry is a folder
holding a `body.md` (plus any attachments alongside it), split into `received/` and
`sent/`. Communications are kept **in their native language** (D-11 English-only does
NOT apply here).

---

## Sub-actions

| Command | Script | Purpose |
|---|---|---|
| `/aidex-comm new received <slug> [--channel email]` | [scripts/new-communication.sh](scripts/new-communication.sh) | Scaffold a received-communication record |
| `/aidex-comm new sent <slug> [--channel whatsapp]` | same | Scaffold an outgoing draft (status starts `draft`) |

`--channel` accepts `email` (default), `whatsapp`, `call`, `meeting`, `other`.

---

## Dispatch

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/new-communication.sh" "$@"
```

The script scaffolds `.context/communications/<received|sent>/<YYYY-MM-DD>-<slug>/body.md`
from the template, refuses to overwrite, and prints the created path on stdout. Fill
`from`/`to`/`subject` and write the body afterward in the native language.

---

## Entry format

```
.context/communications/
  received/<YYYY-MM-DD>-<slug>/body.md   (+ attachments alongside)
  sent/<YYYY-MM-DD>-<slug>/body.md
```

`body.md` front-matter:

```markdown
---
channel: email          # email | whatsapp | call | meeting | other
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

---

## Draft → sent flow

An outgoing message is scaffolded under `sent/` with `status: draft`. When it actually
goes out, set `status: sent` and bump `updated`. A received communication is a record of
what already arrived, so it lands with `status: sent` from the start.

---

## References

- [../aidex-conventions/references/communication-conventions.md](../aidex-conventions/references/communication-conventions.md) — full canon: structure, front-matter, received-vs-sent, draft→sent, English-only exemption, and migrating from legacy `drafts/`.

## Related

- **aidex-request** — for a stakeholder/product *requirement* to act on (the ask), not the raw message; log the message here, capture the requirement there.
- **aidex-conventions** — parent convention for `.context/communications/`.
