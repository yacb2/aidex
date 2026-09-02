# `triage`, `quick-wins` and `detect-resolved` answer three different questions

> Split out of `SKILL.md` under the progressive-disclosure budget in
> `aidex-conventions/references/skill-conventions.md` § Size Constraints.

They are easy to confuse and were, which is why the separation is written down rather
than left to the names.

| Action | Question | Reads |
|---|---|---|
| `triage` | *Is the backlog itself healthy?* Malformed ids, duplicates, items closed but never archived, cross-artifact drift. | front-matter + the index |
| `quick-wins` | *What should I do first?* | front-matter only — **never a body** |
| `detect-resolved` | *Is any of this already done?* | bodies, for the paths and commits they cite |

`triage` is **health, not prioritization**: it will tell you an item is malformed and say
nothing about whether it is worth doing. `quick-wins` is the opposite — it assumes the
backlog is well-formed and answers only about order.

## Running `detect-resolved`

1. `python3 scripts/detect-resolved.py` — the work-list: open items, and per item the code
   paths and commits its body cites. Items with no anchor are marked; they are not worth a
   subagent, because a reviewer would have nothing to open.
2. Fan out **one read-only subagent per anchored item**. Give it the item's title,
   acceptance and anchors, and ask a single question: *does the current code satisfy this?*
   Require a **cited path or commit** in the answer — an unevidenced "looks done" is the
   thing this action exists to replace.
3. Report the suspected-resolved set to the user and stop. **Never close an item from this
   signal**, however confident the subagent sounds. An item can be open for a reason the
   code cannot show: a decision deferred, a follow-up owed, a residual the finding named
   and the commit did not. Closing on code alone is the auto-close defect one layer down.
4. Closing is a separate, deliberate act — `close-item.sh`, with the evidence attached.

## An open error-tracker issue is not open work

An issue sitting in an error tracker's unresolved list only means nobody clicked
resolve. It says nothing about whether the defect still exists. Every event carries a
`release` tag: compare it with what is deployed **before** writing a backlog item.

Items registered from an unresolved tracker list are routinely already fixed and
shipped, and registering one is speculative work on an unreachable path.

The check is two commands, before any design thinking:

```bash
sha=$(git log --format=%H -S "<the raised message>" -- <file> | tail -1)
git merge-base --is-ancestor $sha origin/main && git tag --contains $sha | head -3
```

Then: fixed **and shipped** -> resolve in the tracker, no item. Fixed but local ->
resolve, and say plainly that it is not in production. Still live -> register it.

**Corollary, and the reason a sweep beats one-at-a-time triage:** a shared cause across
many issues is invisible until the whole list — resolved history included — is read
together, not one issue at a time.
