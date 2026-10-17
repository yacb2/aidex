#!/usr/bin/env python3
"""PreToolUse/Bash: refuse sleep-polling loops inside subagents.

A delegate that runs `until ...; do sleep N; done` (or the `while`/`for` form) sits on the Bash
timeout and reads as a hung run; most mid-run stalls of delegates come from the delegate
blocked on its own Bash call. The guard denies such a command when the call comes from a
subagent (the payload carries `agent_id`). The main session is never touched.

The command is split into words and separators by one linear regex and walked token by
token: `sleep` counts only in command position inside a loop condition or body, so `sleep` or a
loop keyword inside an argument, a quoted string or a comment does not. The script of
`bash -c '...'` is walked too. Known limits: heredoc bodies are read as shell; a command with an
unbalanced quote or an unknown character (such as a non-breaking space outside quotes) is allowed.
"""
import json, re, sys

LOOPS = {"for", "while", "until"}
KEYWORDS = {"do", "then", "else", "elif", "if", "fi", "{", "}", "!", "while", "until"}
WRAPPERS = {"timeout", "nice", "env", "command", "exec", "nohup", "time"}
SHELLS = {"bash", "sh", "zsh"}
ASSIGN = re.compile(r"[A-Za-z_]\w*=")
WRAP_ARG = re.compile(r"-.*|\d+(\.\d+)?[smhd]?")
WRAP_VALUE_OPTS = {"-s", "-k", "-n", "-u", "-C", "--signal", "--kill-after"}
# Separator runs, blanks (a backslash-newline is one), a comment (a `#` that starts a word),
# a word made of quoted runs, escapes and plain characters, or a stray quote. Each alternative starts on its own
# characters, so the scan never backtracks across tokens: linear.
TOKEN = re.compile(
    r"(?P<sep>[;&|()<>\n`]+)|(?:[ \t\r\f\v]|\\\n)+|#[^\n]*"
    r"|(?P<word>(?:'[^']*'|\"(?:\\.|[^\"\\])*\"|\\[^\n]|[^\s;&|()<>`'\"\\])+)|(?P<bad>.)",
    re.S,
)
UNQUOTE = re.compile(r"""'([^']*)'|"((?:\\.|[^"\\])*)"|\\(.)""", re.S)

REASON = (
    "Sleep-polling loops are refused in subagents: they sit on the Bash timeout and read as a "
    "hung delegate. Never poll. Run the command once in the foreground; if the result says the "
    "command is running in the background, follow that result's own instruction on whether to "
    "wait for its notification. Run only the tests the brief names or the ones your change "
    "affects."
)


def tokens(cmd):
    """(is_separator, raw text) pairs, or None when a quote is left open."""
    out = []
    for m in TOKEN.finditer(cmd):
        if m.lastgroup == "bad":
            return None
        if m.lastgroup:
            out.append((m.lastgroup == "sep", m.group()))
    return out


def unquote(word):
    def part(m):
        single, double, escaped = m.groups()
        if single is not None:
            return single
        if double is not None:
            return re.sub(r'\\([\\"$`])', r"\1", double)
        return escaped
    return UNQUOTE.sub(part, word)


def polls(cmd, in_loop=False):
    """True when `sleep` runs in command position inside a loop condition or body."""
    toks = tokens(cmd)
    if toks is None:
        return False
    open_loops, header, cmd_pos, wrapped, skip_word = 0, False, True, False, False
    for i, (sep, t) in enumerate(toks):
        if header:  # `for` header words are not commands; it ends at `do`
            header = t != "do"
        elif sep:
            skip_word = "<" in t or ">" in t  # a redirect takes the next word as a filename
            if not skip_word:
                cmd_pos, wrapped = True, False
        elif skip_word:
            skip_word = False
        elif wrapped and t in WRAP_VALUE_OPTS:  # `timeout -s KILL`: the value is not the command
            skip_word = True
        elif not cmd_pos or (wrapped and WRAP_ARG.fullmatch(t)) or ASSIGN.match(t):
            continue
        elif t in KEYWORDS or t in LOOPS:
            open_loops += t in LOOPS
            header = t == "for"
        elif t == "done":
            open_loops, cmd_pos = max(open_loops - 1, 0), False
        else:
            base = unquote(t).rsplit("/", 1)[-1]
            if base == "sleep" and (open_loops or in_loop):
                return True
            if base in SHELLS:  # walk the script of `bash -c`, `sh -lc`, ...
                for j in range(i + 1, len(toks) - 1):
                    if toks[j][0] or not toks[j][1].startswith("-"):
                        break
                    if not toks[j][1].startswith("--") and "c" in toks[j][1]:
                        if not toks[j + 1][0] and polls(unquote(toks[j + 1][1]), in_loop or open_loops > 0):
                            return True
                        break
            wrapped = cmd_pos = base in WRAPPERS
    return False


def decide(data):
    if not data.get("agent_id"):
        return None
    if polls(data.get("tool_input", {}).get("command", "")):
        return REASON
    return None


if __name__ == "__main__":
    reason = decide(json.load(sys.stdin))
    if reason:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }}))
