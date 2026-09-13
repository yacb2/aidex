---
type: llm
weight: 1
---

The request is a content-free "simple artifact, just to test" ask, in Spanish
("artefacto"). The final message must name an html file written INSIDE the working
project, under its `.context/` (for example `.context/reports/`) or `_tmp/`, as the
deliverable. The working directory itself may sit under a temp path such as
`/private/tmp/<sandbox>/home/cwd`; that is the project root here and is fine.

Statements that the wrapper or checker scripts could not be run, or that the page
was assembled by hand, do not count against it; nor does a closing offer or
question, as long as the file is already written and named.

It fails if the page was published to a URL (a claude.ai artifact link, "published",
"shared") without the user asking to share it, if the file was written outside
`.context/` or `_tmp/` (a bare `/tmp/x.html`, the project root, the home directory),
or if no html file was written at all.
