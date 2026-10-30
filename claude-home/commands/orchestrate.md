---
description: Run a fixed chain of agents over one task — plan, implement, test, review, update the docs, commit. The chain has a handoff, a step block, and a plan-confirm stop before the code.
argument-hint: <design|feature|bugfix|test|refactor|review|custom> <description | pull-request URL or number>
---

# Orchestrate

Run a named agent chain over the task in `$ARGUMENTS`. You are the orchestrator. You do not write
the code yourself. Each step is one agent invocation.

## Step 0 — pick the workflow, then show the chain

1. Read the first word of `$ARGUMENTS`. If it names a workflow, use it. The rest is the task.
2. **If the task is a reference instead of a description, resolve it first.** A reference is an
   Azure DevOps URL, a pull-request URL, or a bare work-item number. Read
   `~/.claude/orchestrate/resolve-reference.md` and follow it. Skip this for a pull request.
3. Classify with the routing table below, using the resolved task text. A resolved work item is
   classified on what it asks for, not on where it came from — a defect report routes
   to `bugfix`, a schema change routes to `feature`.
4. Read `~/.claude/orchestrate/<workflow>.md` with the Read tool. Replace `~` with the
   `%USERPROFILE%` path. The table in "Workflows" names the file. If the read fails, stop and say
   so. Never print a chain from memory.
5. Read `~/.claude/orchestrate/shared-steps.md` with the Read tool when the table in "Workflows"
   says so. If the read fails, stop and say so.
6. Print the chosen workflow and the reason in one clause. Then print the chain from the workflow
   file as a numbered list, with the model of each step.
7. Start immediately. Do not ask for permission to begin, unless the workflow is `custom` and the
   agent list is missing.
8. Create the file `<scratchpad>\orchestrate\state.md` with the Write tool. Use the scratchpad path
   from the session environment. Overwrite an old file. Put these items in it: the workflow,
   whether it uses `shared-steps.md`, the chain, the step as "0 of N", the next gate with its reread
   list (read `~/.claude/orchestrate/after-compact.md`), the task, and the work item or "none".

### Routing table

Match top to bottom. The first row that fits wins.

| The task | Workflow |
|---|---|
| Asks where something belongs, what it breaks, or which option to take | `design` |
| Is a pull-request URL, or asks to review a pull request by number | `review`, pull-request mode |
| Is only a reference: a work-item number, or a work-item URL | resolve it in step 2, then classify on the resolved text |
| Asks to add tests, fix a test, or find a flaky test, or reports a test that fails because of the test code, with no production change | `test` |
| Reports wrong behaviour: an error, a test that fails because of production code, a wrong result, a vulnerability, a leaked secret | `bugfix` |
| Asks to review, check, or audit local work or code that already exists, including "is this safe" | `review`, local mode |
| Moves, renames, extracts, or deduplicates code with no behaviour change | `refactor` |
| Adds or changes behaviour, including a database schema, an entity, or a migration | `feature` |

Some tasks get no chain. The list is in `CLAUDE-MAIN.md`, section "Orchestrate multi-step work
yourself". A git operation goes to the `git` agent, because it knows the team rules.

When you skip the chain, say so in one clause. Never start a chain for a one-agent task.

### Model policy

Pass `model` on every `Agent` call. Default to these, and say in one line when you deviate.

| Step | Model | Effort | Why |
|---|---|---|---|
| `architect` | `opus` | `medium` | Judgement. A wrong decision gives a wrong plan |
| `planner` | `opus` | `medium` | Judgement. A wrong plan gives wrong code |
| `pr-reviewer` (`review`, pull-request mode) | `sonnet` | `medium` | The agent file holds the procedure. Its `reviewer` does the judgement |
| implementer agents (`dotnet-developer`, `frontend-developer`, `powershell-developer`, `container-developer`, `markdown-developer`), fix pass | `sonnet` | `medium` | Run one implementer for each chunk, in order. A `mechanical` chunk stays `sonnet`, also when a raise rule applies. The plan holds the decisions, so the step is execution |
| `tester` | `sonnet` | `medium` | The test plan already names what to assert. Raise it to `opus` when its report says "Recommend `opus`", or when the tests must control concurrency or guard a published contract |
| `reviewer` | `sonnet` | `medium` | Raise it to `opus` by the rules in "Reviewer model" |
| `devops`, `git` | `haiku` | `low` | Lookup and fixed rules. Raise it to `sonnet` when the report misses a rule or a file that you can see |
| `Explore`, `explore-web` | `haiku` | `medium` | Search and flow summaries. Raise it to `sonnet` when the report misses a file that you can see. Raise `Explore` to `sonnet` for a flow over more than one project or more than about 5 steps |
| `docs-updater` | `sonnet` | `medium` | It decides which document the change made wrong, and it writes new text |
| `general-purpose`, any other helper agent | `sonnet` | none | The task is open, so the agent file holds no rules for it |

The main session plans, decides, and resolves agent questions.

Raise any other step to `opus` when one of these is true:

- The task is cross-repository.
- The task touches a published contract.
- The user says the change is risky.

#### Reviewer model

`reviewer` goes to `opus` when one of these is true:

- The diff is over about 300 lines or over 5 files.
- The diff touches a published contract.
- The task is cross-repository.
- The user says the change is risky.
- `Focus: security` is on, and the diff changes authentication, authorization, crypto, or secret
  storage. Also when the diff changes a hook, an installer, an update script, or an MCP server entry,
  or when the task reports a vulnerability or a leaked secret.
- `Focus: migration` is on, and the migration drops or renames a column or a table, changes a column
  type, or moves data in a table that already holds data.

`orchestrate.md` and `pr-reviewer.md` hold the same text. Keep the two texts identical.

#### Effort

Read `~/.claude/orchestrate/effort.md` before the first `Agent` call that can pass `effort`. It holds
the small-change test and the rules for the `effort` parameter.

## Workflows

Each workflow has its own file in `~/.claude/orchestrate/`. Step 0 reads the file of the chosen
workflow. It reads `shared-steps.md` only when this table says so.

| Workflow | File | Read `shared-steps.md` |
|---|---|---|
| `design` | `design.md` | no |
| `feature` | `feature.md` | yes |
| `bugfix` | `bugfix.md` | yes |
| `test` | `test.md` | yes |
| `refactor` | `refactor.md` | yes |
| `review` | `review.md` | only when the user asks for a fix pass in local mode |
| `custom` | `custom.md` | only when the agent list names an implementer |

## The guards

A guard adds a `Focus:` line to the `reviewer` handoff. Decide each guard from the diff after the
test step, not from the plan. Why: the plan can miss a SQL file or a configuration change that the
implementer added.

- **The security guard** adds `Focus: security` when the diff touches input handling,
  authorization, data access, file paths, configuration, secrets, crypto, or an outbound call. It
  also fires when the task reports a vulnerability or a leaked secret, or asks whether code is safe,
  or when an implementer report names `Focus: security`.
- **The migration guard** adds `Focus: migration` when the diff contains a migration, a schema
  change, or SQL. It also fires when an implementer report names `Focus: migration`.

Print each guard that fired, and the reason in one clause, in the step block of the review step.
`pr-reviewer` holds the same two conditions. Keep the two texts identical when you change one.

## The handoff

You write the handoff. Each agent gets a prompt built from the previous agent's report, not the
raw report pasted in. Keep a handoff under 30 lines.

```markdown
## Handoff: <previous agent> -> <next agent>

**Task**: <the original task, one line>
**Done so far**: <what the previous steps produced>
**Files touched**: <paths, or "none">
**What you must do**: <the concrete job for this agent>
**Constraints**: <repository rules, decisions already made, paths not to touch>
**Open questions**: <unresolved items, or "none">
```

Rules for the handoff:

- Carry forward every decision that was already made, so the next agent does not re-decide it.
- Carry forward every constraint the previous agent detected, such as an analyzer ban or a
  convention.
- Never carry forward a finding as a fact when the previous agent marked it a question.
- Give `reviewer` the diff base, the scope, the mode (`HUNT` or `VERIFY`), and each `Focus:` line.
  Never paste the diff or the implementer summary.
- Name the plan file of the step by its path, such as `<scratchpad>\orchestrate\plan-implement.md`.
  The agent reads it. Never paste the plan into the handoff.
- Name the output path `<scratchpad>\orchestrate\design-note.md` in the `architect` handoff. The
  agent writes the note there.
  Name the same path in the `planner` handoff. Never copy the note. Tell `planner` that the
  `Files read` list holds the reads of `architect`. Name `<scratchpad>\orchestrate\` as the output
  folder in the `planner` handoff. `planner` writes the plan files there.
- Name the sibling that the new code must match. Tell the implementer to copy the sibling pattern,
  or to use a different pattern in both the new code and the sibling. Never allow a new pattern in
  the new code only. Why: the code keeps one way to do each thing.
- Put the files in the task scope in **Constraints**, and tell the agent to change no other file,
  except a sibling that it aligns by the rule above.

## After each step

Before each implementer or `tester` step, run `git status --porcelain` and keep the output. After
the step, run it again and compare. A file that changed outside the task scope is a finding,
unless the agent report names it as an aligned sibling. Send it back before the next step.

Then print the step block. It has up to 8 lines:

```
Step <n> of <N> done: <agent> — <outcome>
Changed: <up to 5 paths, then +N more>
Verified: <build result, test counts>
Findings: <one line for each blocking finding: path:line — defect>
Open: <questions or assumptions>
Next: <agent> — <job>
```

Omit an empty line, except the first line and `Next:`. Then update `state.md` with the Edit tool.
Put these items in it: the step, the next gate and its reread list, the decisions, each
`New to the repo:` line, the files, the counts, the guards, and the open findings with `path:line`.
`state.md` must hold every count, path, and caveat that the final report needs. Why: a compact can come first.

Then check the compact gates below. At each gate, read the sections of its reread list that you
did not read since the last compact (see `after-compact.md`), also when no compact runs. When no
gate applies, run the next step. Never print the full report of an agent.

When you end a turn only to wait for a background agent, make this the exact last line of the
message:

```
Waiting for agents. Nothing needed from you now.
```

Why: `notify.ps1` matches this line and shows no "Claude: done" toast.

## Before you ask about findings

Before the first findings table, read `~/.claude/orchestrate/findings-rules.md` and follow it. It
holds the rules for `findings.md`. After the answer of the user is in `findings.md`, check gate C.

## The plan-confirm stop

The stop comes after `planner` in `feature`, `bugfix`, and `refactor`. In `custom`, it comes after
`planner` when the list names `planner`. The main session never builds a plan itself.

1. Check that `planner` wrote these files in `<scratchpad>\orchestrate\`. When `planner` returned
   the full plan, split it by its headings into the same files:
   - `plan-implement.md` from `## For the implementer`, or `plan-implement-<n>.md` from each
     `### Chunk <n>` when the plan has more than one chunk
   - `plan-test.md` from `## For tester`
   - `plan-review.md` from `## For the reviewer`
   - `plan-docs.md` from `## For docs-updater`
2. In a file that you wrote, add the acceptance criteria from `## Summary` and the `## Key files`
   list. Skip a file when its section says none. Add the `New to the repo:` lines to each plan-implement file.
3. Write the plan file paths and the decisions into `state.md`.
4. Print the plan from the plan files, the phase list of `planner`, and its `New to the repo:`
   lines. When "How to decide" fires, print the three compact lines too.
5. Stop and wait for "go" (or "continue") or a change.
6. On a change that adds no file and no phase, edit the plan files yourself. On any other change,
   run `planner` again with the change, so that it writes the files again. Then print the plan again.

Do not print the "Waiting for agents" line at this stop.

## Compact gates

`/compact` clears the spent context and keeps a summary. Only the user can run it. No agent can run
it. This section is the only full copy of the compact rules. `CLAUDE-MAIN.md` and the
`strategic-compact` skill point here. Check for a compact gate after each step.

### The four gates

In time order:

1. **Gate A — the design is done.** It is the plan-confirm stop. It comes after the last design
   step, and before the first implementer starts. The last design step is `planner` in `feature`,
   `bugfix`, and `refactor`. Never put the gate between `architect` and `planner`, because the plan
   needs the design note.
2. **Gate B — the code is done.** After each test step that follows an implementer step or a fix
   pass, also the re-test of a fix pass. Also after the browser check step when that step runs.
   Gate B comes before the next review step or `VERIFY` run. `reviewer` reads the diff from disk.
3. **Gate C — the findings are written.** At each findings question, after the round is in
   `findings.md`. Also after a review step or a `VERIFY` run with no blocking finding, before the
   docs step. The fix pass reads `findings.md`, not the context.
4. **Gate D — the task is done.** After the final report. The chain is done. A compact here drops
   the context of the finished task before the next task or the commit.

Gate B and gate C come again in each fix pass.

The `test` workflow has no design step and no implementer. Only gate C and gate D apply to it.

### The block

Never ask for a compact in the middle of one stage. This includes the time while a background agent
runs, and the time before its report is in `state.md`. Why: the next step needs that context.

### How to decide

Ask for a compact at a gate only when both of these are true. Otherwise continue and say nothing.

1. The `[StrategicCompact]` hook printed a message since the last gate. Take C, the context size,
   from the `(Nk of ...)` part of the message. The hook prints a message when the context reaches
   15% of the window, and again at each further 10%.
2. (C - F) x T >= 20 x F.
   - F is the floor after a compact: the value in `state.md`, or 105k when none.
   - T is the number of main-session turns left: about 3 for each remaining step, plus 3 for each
     expected fix pass.

Gate D uses only condition 1.

Why 20: the main session writes the 1h cache at 2x and reads it at 0.1x. Example: C = 166k and
F = 105k give T >= 35. A different area of the code (a different project or top-level folder)
also needs condition 2.

Write F and T into `state.md` at each gate. After a compact, record the real context size as F.

### How to ask

Print these three lines, then stop and wait for the user.

```
Compact gate <A|B|C|D>: <gate name> — <the reason in one clause>
Run: /compact Keep: <the facts the next step needs, one line>
Then say "go". I resume at step <n> of <total>.
```

The `Keep:` line is the focus text for `/compact`. Put the full path of `state.md` first, then the
full path of `findings.md` when it exists. Then put the workflow name, the next gate, the step,
whether the workflow uses `shared-steps.md`, the plan decisions, the file paths, the acceptance
criteria, and the open findings in it. Leave out search results and file contents.

### After a compact

When the user says "go" or "continue" after a gate, read `~/.claude/orchestrate/after-compact.md`
and follow it. It holds the reread table and the steps.

## Stop rules

Stop the chain and report, when:

- An implementer reports the task is blocked.
- A build or a test fails and the implementer could not fix it.
- The user chooses "stop the chain" at the question after a fix pass. See "After each fix pass" in
  `shared-steps.md`. Never stop at that point without the answer of the user.
- `tester` cannot reproduce the bug in the `bugfix` workflow. Do not fix a bug that no test or
  reproduction shows.
- The user interrupts.
- `architect` returned two viable options with a real trade-off. The choice is the user's. Print
  the recommendation and the alternatives, and stop. Do not pick.
- The fix needs a behaviour change for existing callers, and nobody asked for it. Describe the
  choice and stop.

Say which step stopped it and why, in one line. Then print the last step block. When findings
caused the stop, print the findings table too.

## Final report

Read `~/.claude/orchestrate/final-report.md` before the final report. It holds the format.

## Rules

- Run independent agents in parallel, in one message. Never run two implementers on the same file
  at the same time. Never run `tester` and an implementer at the same time.
- In `feature`, `bugfix`, `test`, and `refactor`, never skip one of these steps to save time:
  - the review step
  - the test step (not in `test`, see "Shared steps" in `shared-steps.md`)
  - the docs step
  - the final suite run
  - the commit step
- Never report a step as done when its agent reported a failure.
- Keep every fact from an agent's report: a path, a number, a caveat.
- Effort: see "Effort" and the Effort column in "Model policy".
- The words "go" and "continue" mean the same at every stop.
