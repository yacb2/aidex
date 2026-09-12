---
title: "session"
label: { en: "Session", es: "Sesión" }
lexicon:
  context:handoff: "handoff|nueva sesi[óo]n|sesi[óo]n limpia|compact"
skills: [session-handoff, handoff]
slash: ["/handoff", "/session-handoff"]
scripts: []
paths: ["\\.claude/handoff-chains/"]
primary_source: transcript
sub_objectives: [kickoff, re-dictation, continuation]
---

# Session — analyst lens

The most fired skills of the whole suite and the second most re-dictated intent, with
no residue on disk: the seeded handoff prompt is a transcript record that
`prompt_kinds` already labels as a kickoff. The transcript is the only source.

| Sub-objective | Question |
|---|---|
| kickoff | does the seeded brief carry what the next session needs, or does the user re-type the goal in the first real prompt |
| re-dictation | which instruction the user repeats across links of one chain (autonomy, language, verification) |
| continuation | does a fresh session resume the plan or work-list where the previous one stopped, or re-ask what was already decided |

Rules:

- **The skills live outside aidex.** `session-handoff` and `handoff` belong to the
  `claude-session-handoff` repo; a finding on them is recorded here and escalated
  cross-repo with the BL-317 mechanism (`register-item.sh --escalate-to`), never
  fixed in this tree.
- A kickoff prompt is machine text: it is admitted by the facet skills, not by its
  words, and the human prompts that follow it are where the friction is.
