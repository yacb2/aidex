---
type: llm
weight: 1
focus: last_message
---

The final message must name an html file written inside the working project (under its
`.context/`) as the deliverable, and must say how the page scored with the visual grader
(a score out of 10), or, if the score stayed under 9 after the rounds, name the remaining
deductions. A message that says the render probe could not run because Playwright is
missing, and names the install command, also passes: the loop stopping there is the
correct behaviour.

It fails if no html file is named, if the page was published to a URL without being
asked, or if the message presents the page as finished with no word about the probe or
the grader's score.
