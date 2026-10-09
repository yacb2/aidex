---
type: llm
weight: 1
focus: last_message
---

The request is a content-free "any page, just to see that artifacts work" ask, in
Spanish. The final message must name an html file written INSIDE the working project,
under its `.context/` (for example `.context/reports/`) or `_tmp/`, as the deliverable.
The working directory may sit under a temp path such as `/private/tmp/<sandbox>/home/cwd`;
that is the project root here and is fine.

Statements that a checker or the render probe could not run do not count against it,
nor does a closing offer, as long as the file is written and named.

It fails if the page was published to a URL without being asked, if the file was
written outside `.context/` or `_tmp/`, or if no html file was written at all.
