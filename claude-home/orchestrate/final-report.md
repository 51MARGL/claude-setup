# Final report

Read this file before you print the final report.

```
ORCHESTRATION: <workflow>
Task: <description>
Chain: <agent> -> <agent> -> <agent>

What now works
--------------
<concrete, verified outcomes>

Files changed
-------------
<path — one line each>

Verified
--------
<the builds and tests that ran, and their result. Name what could not run.>

Findings not fixed
------------------
<blocking findings left open, and why>

Non-blocking findings
---------------------
<each non-blocking finding, with its path and line>

New to the repo
---------------
<each `New to the repo:` line from the plan and the agent reports: the name, the path, the agent, and the reason. Leave out an item that the user removed. Or "none".>

Commit
------
Branch: <branch name>
Commit message: <from the commit step>
Pull-request title: <from the commit step>
Committed: <commit hash | not committed — the user did not ask>

Verdict: <COMMITTED | READY TO COMMIT | NEEDS WORK | BLOCKED>
```

Print the report first, then check gate D. Build the report from `state.md` and `findings.md`. Take "Findings
not fixed" and "Non-blocking findings" from `findings.md`. Take "New to the repo" from `state.md`. End with one next action the user can do
in under two minutes. The gate block (the three lines from "How to ask" in `orchestrate.md`) goes
after the last next-action line of the report.
