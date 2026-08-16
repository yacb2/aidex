#!/usr/bin/env python3
"""prompt_kinds.py — decide whether a transcript record is something a HUMAN typed.

Every usage-retro number is a rate over "user prompts", so the predicate that
defines a user prompt sets the denominator of the whole study. It was wrong.

WHAT WENT WRONG
---------------
Claude Code delivers a lot of machine-authored text as records with
`type="user"` and plain markdown content: SDK-driven harnesses (security-review,
the durability-arbiter Stop hook), expanded skill bodies (artifact-design,
artifact-diagramming), expanded slash-command bodies (`# /handoff`,
`# version:release`), compaction summaries, and the kickoff positional that
`claude-session-handoff`'s wrapper passes to the session it launches.

None of it starts with an angle bracket, so the previous predicates — which
rejected only `<`-prefixed text and a short prefix tuple — passed all of it
through as typed input. Measured over 2026-07-23..2026-08-16 (938 sessions,
2,208 user-typed records): **38.4% of the "prompts" were machine-authored**
(29.8% injected bodies, 8.5% wrapper kickoffs). Every rate the retro has
published for three runs carried that inflation in its denominator, and the
per-model "autonomy nudge" table was 70% wrapper kickoffs.

HOW THIS DECIDES
----------------
Structurally first, by content only as a fallback. Claude Code stamps the
provenance fields the answer needs:

  origin.kind == "human"   set on genuinely typed input (1,474 records in the
                           validation window, ZERO of them injected — exact)
  promptSource == "typed"  the same signal on records predating `origin`
  promptSource == "sdk" /  the harness speaking through the user channel
  entrypoint "sdk-*"
  isMeta                   image-paste placeholders and re-invocation notices

`origin.kind` is checked FIRST and wins, because a genuine prompt from the
desktop app carries `promptSource="sdk"` alongside `origin.kind="human"` — the
order is what keeps 64 real prompts from being discarded.

INJECTED_PREFIXES is the fallback for transcripts written before the provenance
fields existed. It is a *safety net for old data*, not the primary mechanism;
adding to it is fine, relying on it for new data is not. Every entry was
validated against real transcripts — none is speculative.

CONTRACT
--------
`classify_session` returns a kind for every user record, and **`injected` and
`kickoff` are returned, never silently dropped**. A miner that hides them
reproduces the original bug in a new place: the point is that the denominator
is visible and auditable, not that it is quietly smaller.

Pinned by `skills/aidex-audit/tests/test-prompt-kinds.sh`.
"""
import json
import re

# Kinds. `real` and `slash` are human; `injected` and `kickoff` are machine;
# `skip` is not a prompt at all (tool results, envelopes, image placeholders).
REAL, SLASH, INJECTED, KICKOFF, SKIP = "real", "slash", "injected", "kickoff", "skip"
HUMAN_KINDS = (REAL, SLASH)
MACHINE_KINDS = (INJECTED, KICKOFF)

# Harness envelopes: not prompts in any sense.
SYS_PREFIXES = (
    "<task-notification", "<local-command", "<bash-", "<system-reminder",
    "<command-message>", "[Request interrupted", "Caveat:",
    # The Skill tool's expanded SKILL.md arrives through the user channel.
    "Base directory for this skill",
)

# Machine-authored bodies that reach the user channel as plain markdown.
# Fallback only — see the module docstring. Counts are from the validation
# window and exist so a future editor can tell a live entry from a dead one.
INJECTED_PREFIXES = (
    "Review this change for security vulnerabilities.",   # 496 — /security-review
    "You previously flagged these candidate vulnerabilities",  # 95 — its 2nd pass
    "Approach this as the design lead",                   # 55 — artifact-design body
    "You are the durability-arbiter",                     # 27 — Stop-hook payload
    "This session is being continued from a previous conversation",  # 11 — compaction
    "Provide a code review for the given pull request",   # 7 — /code-review body
    "Run the workflow-backed code review",                # 6 — /code-review ultra
    "(Re-invocation of",                                  # 6 — skill re-entry notice
    "Stop hook feedback:",                                # 4 — Stop-hook relay
    "Draw as the engineer",                               # 4 — artifact-diagramming
)

# An expanded slash-command body opens with its own name as an H1.
_COMMAND_BODY_RX = re.compile(r"^#\s+(/|[a-z][\w-]*:)", re.I)

# A bare slash command the user typed.
_SLASH_RX = re.compile(r"^/[a-z][\w:-]*\s*$", re.I)

# The kickoff positional `claude-session-handoff` passes to the session it
# launches (scripts/claude-wrapper.sh: `run_claude "continue"`). It exists
# because SessionStart's `initialUserMessage` is accepted and silently ignored
# by Claude Code — re-probed on 2.1.221/223/224. So this is correct behaviour
# being excluded, not a bug being counted.
_KICKOFF_RX = re.compile(r"^(continue|continua|contin[uú]a|adelante|sigue|sigamos)[\s.!,]*$", re.I)

HANDOFF_MARKER = "=== HANDOFF FROM PREVIOUS SESSION ==="
_HANDOFF_HEAD_RECORDS = 12   # the marker rides in the SessionStart hook attachments


def _text_of(o):
    """The user-visible text of a record, or None when it is not text at all."""
    c = o.get("message", {}).get("content")
    if isinstance(c, list):
        if any(isinstance(x, dict) and x.get("type") == "tool_result" for x in c):
            return None
        c = "\n".join(x.get("text", "") for x in c
                      if isinstance(x, dict) and x.get("type") == "text")
    if not isinstance(c, str):
        return None
    return c.strip() or None


def classify(o):
    """(kind, text) for one record. Never returns KICKOFF — that needs the session.

    Returns SKIP with an empty string for anything that is not a prompt.
    """
    if o.get("type") != "user" or o.get("isSidechain") or o.get("isMeta"):
        return SKIP, ""
    text = _text_of(o)
    if text is None or text.startswith(SYS_PREFIXES):
        return SKIP, ""

    if text.startswith("<command-name>"):
        inner = text.split("<command-name>", 1)[1].split("</command-name>", 1)[0].strip()
        return SLASH, inner

    kind = SLASH if _SLASH_RX.match(text) else REAL

    origin = (o.get("origin") or {}).get("kind")
    source = o.get("promptSource")
    entry = o.get("entrypoint") or ""

    # Positive human markers win outright: a desktop-app prompt carries
    # promptSource="sdk" together with origin.kind="human".
    if origin == "human" or source == "typed":
        return kind, text
    if source == "sdk" or entry.startswith("sdk"):
        return INJECTED, text
    if text.startswith(INJECTED_PREFIXES) or _COMMAND_BODY_RX.match(text):
        return INJECTED, text
    return kind, text


def is_handoff_seeded(objs):
    """True when this session was opened by claude-session-handoff with a payload."""
    for o in objs[:_HANDOFF_HEAD_RECORDS]:
        if HANDOFF_MARKER in json.dumps(o):
            return True
    return False


def classify_session(objs):
    """[(index, kind, text)] for every user record in one session's records.

    The only classification that needs whole-session context is KICKOFF: the
    wrapper's positional is indistinguishable from a typed "continue" except
    that it is the FIRST human-looking prompt of a handoff-seeded session.
    """
    seeded = is_handoff_seeded(objs)
    out = []
    first_human_seen = False
    for i, o in enumerate(objs):
        kind, text = classify(o)
        if kind == SKIP:
            continue
        if kind in HUMAN_KINDS:
            if seeded and not first_human_seen and _KICKOFF_RX.match(text):
                kind = KICKOFF
            first_human_seen = True
        out.append((i, kind, text))
    return out


def is_real_user(o):
    """Record-level convenience: did a human type this?

    Cannot see the wrapper kickoff (that needs the session), so a caller whose
    question is "did a human speak in this session" should use
    `classify_session` instead — a handoff-seeded session whose only human-
    looking record is the kickoff has no human in it.
    """
    return classify(o)[0] in HUMAN_KINDS
