# Before you ask about findings

Read this file before the first findings table.

Write the findings file first: `<scratchpad>\orchestrate\findings.md`. Create it with the Write
tool. Add to it with the Edit tool. Write its full path into `state.md`.

Add one section for each review round, with the heading `Round <n>`. A round is one review step or
one `VERIFY` run. Put these items in the section:

1. The full table. Use one row for each finding. Use these columns:
   - severity
   - `path:line`
   - defect
   - trigger and what breaks
   - owner
   - fix
2. For each finding, whether the main session checked it, and how.
3. The answer of the user.
4. The status of each finding: `open`, `fixed`, `verified`, or `skipped`.

Write items 1 and 2, and the status `open`, before you print the table. Write item 3 and the new
status when the user answers. After each fix pass and each `VERIFY` run, update the status of each
finding.

Then print the table in the chat, with the same rows. Then follow "Put the items into the question"
in `CLAUDE-MAIN.md`. After the answer is in `findings.md`, check gate C.

A review round with no blocking finding gets a section too. Write it before the docs step, and then
check gate C.