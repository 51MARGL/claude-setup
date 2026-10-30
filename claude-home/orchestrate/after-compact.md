# After a compact

Read this file when the user says "go" or "continue" after a gate.

Why: a compact turns the earlier reads into a summary, and a step must not run from memory. Read
only the sections that the next steps use. The full files cost more than the sections.

After a compact, Claude Code injects `orchestrate.md` again. Read the files and sections in the
table below. Find the gate in the table. Each name in the table is a heading of the file. A heading
includes its subsections.

| Gate | Other files | `shared-steps.md` sections |
|---|---|---|
| A | `findings-rules.md`, `effort.md` | Shared steps (the lines above the first `##` heading), The branch step, The test step, After each fix pass, The browser check step (`feature` and `bugfix` only) |
| B | `findings-rules.md`, `effort.md` | Shared steps (the lines above the first `##` heading), The fix pass, The test step, The browser check step (`feature` and `bugfix` only) |
| C | `findings-rules.md`, `effort.md`, `final-report.md`, `resolve-reference.md` (only when `state.md` names a work item) | Shared steps (the lines above the first `##` heading), The fix pass, The system-wide impact check, The test step, The browser check step (`feature` and `bugfix` only), The docs step, The final suite run, The commit step |
| D | none | The commit step |

The rows are not cumulative. A gate can pass with no compact. Then read at that gate only the
sections of its row that you did not read since the last compact. Use the steps below.

Do these steps. Replace `~` with the `%USERPROFILE%` path.

1. Read `<scratchpad>\orchestrate\state.md`. It names the next gate and its reread list.
2. Run Grep with `-n` and the pattern ``^(#{2,4} |```)`` on `shared-steps.md`.
3. Read each listed section with the Read tool. Set `offset` to the heading and `limit` to the lines
   up to the next heading of the same or a higher level. A heading line between two ``` lines is
   inside a code block. It is not a heading.
4. Read `~/.claude/orchestrate/<workflow>.md` in full. It is short.
5. Read `<scratchpad>\orchestrate\findings.md` when `state.md` names it.
6. When the user gives a change at gate A and not "go", read "The plan-confirm stop" in
   `orchestrate.md` too.
7. If the Grep or a section read fails, read the full file. If that read fails too, stop and say so.

After gate D, the final report is already printed. When the user says "commit", read `state.md`
and the sections of row D. Then run the commit step. A new task in the same session starts at Step 0, which reads
the files of its own workflow.
