"""_reference_reads.py — what mine-reference-reads.py and sweep-reference-reads.py share:
which tool calls count as pulling a file into context, how a fired skill is named, and
the walk over one transcript's tool calls. Not a command; import it."""
import json


def pulls_into_context(name, inp):
    """The text of a tool call that would put a file's CONTENT into the context window
    (a Read path, a Bash command, a Grep path+glob); '' for any other call."""
    if name in ("Read", "NotebookEdit"):
        return str(inp.get("file_path", ""))
    if name == "Bash":
        return str(inp.get("command", ""))
    if name == "Grep":
        return str(inp.get("path", "")) + " " + str(inp.get("glob", ""))
    return ""


def bare_skill(name):
    """aidex fires as `aidex:<name>`; citations and --when-skill are keyed bare. Another
    plugin's `x:<name>` is returned unchanged, so a caller can tell it apart."""
    return name[len("aidex:"):] if name.startswith("aidex:") else name


def tool_uses(path, stats=None):
    """(tool name, input) of every tool_use block on the assistant lines of a transcript.
    A line that is not JSON is skipped and counted in stats['skipped'] when stats is given.
    An unreadable file raises OSError on the first step; each caller skips such a file."""
    for l in open(path, errors="replace").read().splitlines():
        if not l.strip():
            continue
        try:
            o = json.loads(l)
        except (ValueError, RecursionError):
            if stats is not None:
                stats["skipped"] = stats.get("skipped", 0) + 1
            continue
        if o.get("type") != "assistant":
            continue
        for b in o.get("message", {}).get("content", []) or []:
            if isinstance(b, dict) and b.get("type") == "tool_use":
                yield b.get("name") or "", b.get("input") or {}
