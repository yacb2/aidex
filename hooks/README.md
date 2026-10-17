# Shipped hooks

The wired hooks are listed in `hooks.json`. The retired router and durability hooks (and their README) live in `docs/retired/hooks/`.

## context-depth-nudge.sh — context-depth band notice (UserPromptSubmit)

> **Opt-in, like every hook here.** `install.sh` copies this file to
> `~/.claude/hooks/` (it is the one hook in `SHIPPED_HOOKS`) and wires nothing —
> settings.json is never touched. Installing or
> updating aidex therefore activates nothing. It runs only if you add it to your
> own `~/.claude/settings.json` yourself (see Registration below). The thresholds
> below were tuned on one person's corpus; treat them as a starting point, not a
> default anyone should inherit.

Surfaces how deep the session's context has grown, once per band, as one line of
`hookSpecificOutput.additionalContext`. Bands: **200k** warn, **250k** advise,
**300k** urgent. Silent below 200k and silent on every later prompt in a band it
already announced. Never blocks; any failure (no jq, missing/malformed transcript,
malformed payload) exits 0 with no output.

**Where the numbers come from.** Measured over 674 Opus 5 sessions / 86,800 turns
(`.context/research/2026-08-13-session-token-threshold-handoff.md`): 87.9% of all
input tokens are spent at depth >=150k; a within-session paired test puts turns at
150-200k at 1.41x the seconds-per-output-token of the same session below 100k,
rising to 1.73x at 400-600k; and a counterfactual replay puts the marginal knee
(tokens saved per additional handoff) between 200k and 250k depending on how
expensive re-entry is assumed to be. 150k was rejected — worst marginal return of
the candidates.

**Why it counts but does not decide.** It does not judge whether to hand off and
does not fire one. The retired durability Stop hook (`2ca548a`) ran a `claude -p`
judge over exactly that call and measured 4 real blocks, 0 justified, 4 misfires,
all on terminals the policy was supposed to allow. Counting tokens is arithmetic
and cannot misfire; judging whether a thread is mid-hypothesis is what did.
`UserPromptSubmit` rather than `Stop` for the same reason — `Stop` can only act by
blocking, the retired failure mode — and because a prompt boundary is where a
handoff is cheapest anyway.

**Depth is `max` over `usage.iterations`, not the top-level sum.** Top-level
`usage` *adds* the iterations of a multi-iteration turn: one observed turn reported
`cache_read_input_tokens: 1,170,043` against a 1M window because its three
iterations (584k/588k/585k) were summed. That figure is what was billed, not what
occupied the window; using it would fire the 300k band at ~100k of real depth on
any turn that iterated three times. Reads the last 400 lines only, so cost does not
grow with transcript size.

**Registration (opt-in, not done by install.sh):** wire it as a `UserPromptSubmit`
hook in settings.json pointing at `~/.claude/hooks/context-depth-nudge.sh`. Pairs
with a statusline that colours on absolute depth rather than percent-of-window —
on a 1M model, 400k reads as 40% and colours green under a percentage scheme.

> **If you build that statusline, do not use `context_window.total_input_tokens`.**
> It carries the same iteration-summing inflation as the transcript's top-level
> `usage`. Observed 2026-08-13: Claude Code reported 394,807 while the window held
> 198,928 — a 1.98x overstatement that read as red on a green session. The visible
> symptom is a number that *drops*: across 96 consecutive turns in that session,
> real occupancy never fell once, while the reported figure fell 5 times, each time
> a multi-iteration turn was followed by a single-pass one. Compute depth from
> `transcript_path` with the same `max`-over-iterations rule this hook uses, and
> fall back to `context_window` only when no transcript is available.

**Tests:** `python3 test-context-depth-nudge.py` — 22 checks, self-contained
(synthetic transcripts, no dependency on real ones). Covers exact band boundaries,
the max-over-iterations rule, post-compaction depth drops, once-per-band gating
with escalation, six fail-open paths, and the non-blocking output shape.

### Sunset criterion (falsifiable — retire if it fails)

Handoffs already fire at a median depth of 337k on Opus 5, but that depth is not a
choice: trigger depth tracks session *peak* depth at ~1.0x, so no depth-based
trigger is operating today at all. There is therefore no evidence a depth cue will
change timing. Due **2026-09-03**:

> Re-run the predecessor->successor trigger query over Opus 5 sessions started
> after 2026-08-13. **Keep** if the median trigger depth falls below 300k *and*
> below that window's median session peak — the second clause is the real test,
> since merely dropping alongside peak would prove nothing. **Retire** if the
> median trigger still tracks peak within +/-10%, or if the nudge fires more than
> 3x in a median session (noise, not signal).

## references-root-gate.sh — no dated file at `.context/references/` root (PreToolUse/Write)

Denies a `Write` of a dated file (`YYYY-MM-DD-*`) directly under a project's
`.context/references/`. That folder is evergreen by name; a dated write-up there is
research's spike shape in the wrong folder, and until 2026-09-21 nothing refused it — the
ISO name passed `validate.py` and no skill runs when a session writes a finding by hand
(17 such files in one workspace in six days). The deny reason carries the routing of
`00-global.md` §8.1, so the block names the right home. `validate.py` rule
`reference-dated-file` is the same check after the fact, for files that arrive by `mv`.

Write only (an Edit never creates a file), path match only, fail-open on any error.
Sunset review 2026-12-21, criterion in the script header.

**Tests:** `python3 test-references-root-gate.py` — 12 checks.

## generated-html-edit-gate.sh — a spec-built page is edited through its spec (PreToolUse/Write, Edit, MultiEdit)

Denies a `Write`, `Edit` or `MultiEdit` of an existing `.html` file whose line 1 is the
`spec_build.py` marker (`<!-- GENERATED from <spec> by /aidex:artifact spec_build.py ... -->`).
The reason names the spec (resolved against the page's directory) and says to edit it and
rebuild with `spec_build.py`. LOOP-012 F10: a Read of a built page shows plain HTML and an
edit request hand-edited the build output, lost at the next rebuild. A new file, an HTML
without the marker, a board's `GENERATED <timestamp>` header, a non-HTML file and any error
pass silently, and so does a marker whose spec no longer exists (the rebuild is impossible). The
`.aidex-artifact-prev/` baseline copy names the same spec as its page. Edit tools only: `sed` or
`python` through Bash is not covered. Sunset review 2026-12-21: a deny is justified when the session
then edits the spec and rebuilds, not when it switches to a Bash rewrite.

**Tests:** `python3 test-generated-html-edit-gate.py` — 17 checks.

## first-test-write-gate.sh — the first new test file waits for the testing core (PreToolUse/Write, Bash)

Denies the first `Write` — or `Bash` command — that creates a test file that does not exist yet, once per
`(session_id, agent_id or "main")`; the retry, and every later new test in that context,
goes through. The reason points to `/aidex:testing` and asks for its questions to be
answered before writing again; it never restates them (`skills/testing/tests/test-single-source.sh`).
It starts with the literal `aidex:testing`, which is how a reader of a transcript
recognizes the gate. `skills/testing/scripts/census.py` does **not** count the deny as
"core in context": the reason is only a pointer, so counting it would measure "the hook
fired"; the Skill load or Read it leads to is what counts. Measured shape: the 2026-09-25 probe denied 6/6,
changed the first landed file 6/6, cost one extra Write each.

Test paths: `test_*.py`, `*_test.py`, `*.{spec,test}.{ts,tsx,js,jsx,mjs,cjs}`,
`test-*.sh`, any `*.sh` under a `tests/` dir — census.py's `TEST_RE`, imported. A Bash
command's written paths come from census.py's `bash_writes`: unquoted `>`/`>>` targets
(heredocs included; a quoted `'>'` or a `# comment` is not a redirect), `tee`, `touch`, and
`open(p, 'w'|'a'|'x')` / `Path(p).write_text(` inside `python -` heredocs and `python -c`
(a literal, or a name resolved against the assignment in effect). Relative paths follow
`cd`/`pushd`/`popd` and `( )` subshells from the event's `cwd` — subagents open nearly every
command with `cd /abs && ...` — and `$VAR`s assigned earlier in the command are substituted;
a path still holding a `$` is unknown and is never denied (the census still counts it).
`cp`/`mv` are not writes: they copy or move a test, they do not author one. The
2026-09-25 eval wrote its first test through Bash in 4 of 12 runs. `sed -i`, test runs,
reads and anything unparseable pass.
Edit/MultiEdit, a write over an existing file and non-test paths pass and write no state.
Main is keyed by the ABSENT `agent_id` (what main sends); a present value, even `""`, is
keyed as itself. No `session_id`: allow, no state. State:
`~/.claude/aidex/first-test-write/<session>.tsv`, checked and appended under `flock`, so
parallel Writes from one context get exactly one deny. Fail-open on any error.

**Tests:** `python3 test-first-test-write-gate.py` — 109 checks, including the pattern
table and the Bash command table (with the eval's verbatim commands, in
`test-first-test-write-gate.eval-commands.json`) run through census.py too.

## artifact-open-once.sh — one open per page per user turn, the build lock, and the kit gate (PreToolUse/Bash)

Three rules, all deterministic, per PAGE. The hook's own header carries the full
reasoning; this is the map.

1. **Once per user turn** (BL-294, 2026-09-01). A path already `open`ed since the last
   thing the user said is refused. Per turn and never per session, because a
   consultation page is contractually re-wrapped and re-opened every time the reader
   answers; blocking that loop would train the override into a habit.
2. **Not while an agent is still building it** (2026-09-20). A page with a fresh
   `<dir>/.aidex-artifact-prev/<page>.building` beside it is refused, with the message
   that only the agent's hand-back ends a build. The lock is written by
   `wrap-report.sh --building` on every wrap of a delegated build and removed by
   `wrap-report.sh --done --out <page>`; a lock older than **20 minutes** is stale, so
   the open goes through and the hook says the build never ended.

3. **Not outside the kit** (2026-10-06, LOOP-008). An `open` of an existing `.html`
   under `/.context/reports/`, `/.context/artifacts/` or `/_tmp/ui-contract/` that lacks
   `<meta name="artifact-kit"` (same recognizer as `check_artifact.py` KIT_STAMP) is
   refused, naming the `/aidex:artifact` spec route and `::: gallery rows=`. Applies to
   subagents too; `open -R/-t/-e`, other folders (communications, proofs, skills), URLs
   and non-html pass.

The second rule exists because a delegated artifact agent writes its final `--out`
path two or three times mid-run (16 of 37 runs), and an intermediate wrap can PASS
`check-artifact.sh` — so neither "the file changed" nor "the gate is green" means the
agent finished. The incident is
`.context/research/2026-09-20-artifact-seen-before-the-agent-finishes.md`: the page
was opened 1 min 41 s before the hand-back, on a state the agent then changed.

**Why the lock is per page and not per pending agent.** The obvious guard — refuse
`open` while any async agent has not handed back — was replayed over every main session
since 2026-09-14 and blocked **18 of 26** real opens, nearly all of them pages no
pending agent was touching. That is the retired durability hook's failure shape. A file
beside the page has no opinion about the transcript.

**What a path has to look like to be seen.** Targets are resolved from the command
text, so three spellings of one page all count as that page: the bare path, a
`file://` URL (`localhost` host tolerated, tried both raw and percent-decoded) and
a `#fragment`. The literal spelling is always tried first, so a filename that really
contains a `#` or a `%20` is still tracked as itself. **Unguarded, on purpose:
a relative path after a `cd`** (`cd /dir && open page.html`) resolves against the
session's working directory, not the `cd` target, so it may miss the page entirely.
Tracking `cd` across command segments would mean interpreting the shell — variables,
`cd -`, subshells — and a friction guard that guesses wrong in that direction blocks
the wrong file. Pass an absolute path, which every documented flow already does
(`wrap-report.sh` prints one).

**One JSON object per invocation**, always. A stale-lock notice rides on whatever the
hook decides as `systemMessage`; it is never an answer of its own. Printing it
separately and falling through wrote two objects on stdout, which parse as neither —
and the verdict in the second one was lost.

**Tests:** `python3 test-artifact-open-once.py` — 99 checks, self-contained. The refusal
cells are the cheap half; the allow cells are the point (consultation loop, a different
page, a URL, a non-`open` command, a stale lock, and five fail-open paths). The
producing half of the lock is `skills/artifact/tests/test-build-lock.sh`.

## subagent-poll-guard.py — no sleep-polling loops inside subagents (PreToolUse/Bash)

Wired in `hooks.json` on the `Bash` matcher. When the payload carries `agent_id` (the call
comes from a subagent), the hook splits the command into words and separators with one linear
regex (quotes and comments kept apart) and walks the tokens, tracking command position and
loop depth. It answers `permissionDecision: deny` when `sleep` (also `/bin/sleep`, or behind
`timeout`, `nice`, `env` and similar wrappers) runs in command position inside a `for`, `while`
or `until` body or a `while`/`until` condition, including the script of `bash -c '...'`. Only a
`done` in command position closes a loop, so `out/done` or `echo done` does not. The reason says
never poll, run the command once in the foreground and, if the result says it is running in
the background, follow that result's own instruction. The main session is never touched; a
loop without `sleep`, `sleep` as an argument, in a quoted string or a comment, `sleep.sh` and a
`sleep` after `done` are allowed. Heredoc bodies are read as shell, and a command with an
unbalanced quote is allowed. Why: a delegate polling on its own Bash call sits on the timeout
and reads as a hung run.

**Tests:** `python3 test-subagent-poll-guard.py` — 53 checks from one table: 46 cells on
`decide()` (deny cells per loop shape, `done` sentinel, wrapper, path, line continuation,
`bash -c` form and a backgrounded poll; allow cells for poll shapes inside arguments, quotes,
comments and commit messages, and a `done` right after `}` or `fi`), 4 on the `REASON` text
and 3 timing rows (each long input under 1 s).
