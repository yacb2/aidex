# Route every prompt: delegate what needs no conversation

**Before writing any Agent brief, or when unsure whether to delegate, split or fan out, load
the `aidex:delegation-detail` skill** (brief shape, depth floors, unit cap, fan-out, liveness,
impl loop). Below ~90k of context (sonnet agents) or ~125k (opus agents), keep work here unless the part is itself token-heavy.
Loaded or not, every brief carries two named sections: **"Files to read first"** as its
first step, and **"what you deliberately left alone"** inside what to return.

**Before the first tool call of every prompt, cut it, then route each part.** A prompt is rarely one kind of work: "commit the plan and start phase 1" carries an implementation, a lookup or a synthesis glued to a commit or a decision. List the parts, launch the agent for each part that needs no conversation in the same turn (in parallel, one message), keep here only the parts that need this conversation.

**While a subagent is running, give no substantive answer and open nothing it is writing.** Do every part whose inputs are already here; then close the turn with one line naming what is pending. That line is the whole reply: no table, no recap, no preview of what the delegate will find. The only signal that a delegate finished is its own hand-back.

| The prompt asks to | Agent |
|---|---|
| investigate outside the repo, compare tools, find prior art, read library docs | `aidex:research-sonnet` |
| find, check, list or count across more than three files or transcripts | `aidex:lookup-sonnet` |
| explain or write prose from existing files (note, section, plan text, table) | `aidex:synthesis-sonnet` |
| fix a reproducible bug | `aidex:bugfix-opus`, then review the diff, check both proof lines and commit here |
| build something already decided that has a test or gate | `aidex:impl-sonnet` |
| run a gate, full suite, E2E red proof or HTTP smoke and report it, fixing nothing | `aidex:gate-runner` |
| file or register findings as backlog items | `aidex:backlog-filer` |
| verify, reproduce or show something in the running app in the browser against measurable expectations (overflow, contrast, clipping, overlap, focus ring, spacing, a named state) | `aidex:verify-browser-sonnet` at medium |
| judge a screen's appearance where no measurable property decides (hierarchy, balance, "does it look right") | `aidex:verify-browser-opus` |
| walk a functional smoke flow in the running app (one flow, one persona per brief) and report pass/fail per step | `aidex:smoke-sonnet` |
| an artifact page / a figure for it | `aidex:artifact-sonnet` / `aidex:figure-sonnet` |
| any other self-contained action with no user decision inside | `aidex:task-general` |

**Always name a roster agent in `subagent_type`;** never `general-purpose` or `Explore`. No fit -> `aidex:task-general`.

**Stays here:** a decision or a question to the user; a read of one to three calls; commit,
release, deploy or anything in production; reviewing a delegate's diff; work that uses a
logged-in personal browser session; the conversational part of a turn that continues an
answer the user just gave (the work that answer unlocks still routes by the table).

**Before committing a delegate's diff, one shape goes to `aidex:review-diff-opus` first:** a diff
that adds or moves a comparison, a quantifier, a boundary or a null/empty branch inside a
predicate. The trigger is the shape, never the model that wrote it. Not on read-only delegates,
prose, layout, file moves or config edits, and not on every unit: a review costs about what
the unit it reviews costs.

**A delegate's diff that changes what a screen does goes through the browser before the
commit:** `aidex:smoke-sonnet` for behaviour (the flow the diff touched),
`aidex:verify-browser-sonnet` for measurable appearance, `aidex:verify-browser-opus` for
judgment-only appearance. `aidex:review-diff-opus` reads predicates and cannot see these.
