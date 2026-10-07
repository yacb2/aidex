"""One-line usage errors for the artifact scripts (script contract, Phase B).

A wrong, unknown or missing argument exits 2 with ONE stderr line that starts
`usage:` and names the valid form. `--help` still prints argparse's full help and
exits 0. Exit 1 stays reserved for a gate refusal of content.
"""
import argparse
import sys


def usage_line(form, why=None):
    line = "usage: " + form
    if why:
        line += "  -- " + " ".join(str(why).split())
    return line


def usage_exit(form, why=None):
    sys.stderr.write(usage_line(form, why) + "\n")
    raise SystemExit(2)


class UsageParser(argparse.ArgumentParser):
    """`form` is the valid call. `hints` maps a flag to the form of the call that
    takes it, for a flag that belongs to another verb or script: the line keeps THIS
    parser's form and adds where the flag lives."""

    def __init__(self, *args, form=None, hints=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.form = form or self.prog
        self.hints = hints or {}

    def error(self, message):
        for flag, form in self.hints.items():
            if flag in message:
                usage_exit(self.form, "%s (%s is taken by: %s)" % (message, flag, form))
        usage_exit(self.form, message)


def read_stdin(form, binary=False, blank_is_empty=False):
    """The bytes (or text) piped on stdin. Nothing piped, or a terminal that would
    block waiting for input, is a usage error naming the valid form: exit 2, one
    line. With `blank_is_empty`, whitespace-only input counts as nothing too."""
    if sys.stdin is None or sys.stdin.isatty():
        usage_exit(form, "no content on stdin (stdin is a terminal)")
    data = sys.stdin.buffer.read() if binary else sys.stdin.read()
    if not (data.strip() if blank_is_empty else data):
        usage_exit(form, "no content on stdin")
    return data
