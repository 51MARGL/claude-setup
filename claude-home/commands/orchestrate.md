---
description: Run a fixed chain of agents over one task — plan, implement, test, review, update the docs, commit. The chain has a handoff between each step and a step line after each step.
argument-hint: <design|feature|bugfix|test|refactor|review|custom> <description | pull-request URL or number>
---

# Orchestrate

Run a named agent chain over the task in `$ARGUMENTS`. You are the orchestrator. You do not write
the code yourself. Each step is one agent invocation.

## Step 0 — pick the workflow, then show the chain

1. Read the first word of `$ARGUMENTS`. If it names a workflow, use it. The rest is the task.
2. **If the task is a reference instead of a description, resolve it first.** A reference is an
   Azure DevOps URL, a pull-request URL, or a bare work-item number such as `32617`. Run
   `devops` on it before anything else, and ask it for the title, the description, the
   acceptance criteria, the state, the linked work items, and the linked pull requests.
   - Give `devops` these values:
     - `BaseUrl` and `Project`: from the URL of the user. Else from the remote URL. Run
       `(git remote get-url origin) -replace '^(https?://)[^/@]+@', '$1'`, so the raw URL never
       prints. Never put a user name or a token from a remote URL into `BaseUrl`.
       The HTTPS form is `dev.azure.com/<org>/<project>/_git/<repo>` or
       `<server>/<collection>/<project>/_git/<repo>`. The SSH form is
       `ssh.dev.azure.com:v3/<org>/<project>/<repo>`. Else ask the user.
     - `Auth`: the user gives it in the chat. It is a PAT, the name of an environment variable, or
       `default-credentials`. Pass it as `Auth: pat:<token>`, `Auth: env:<NAME>`, or
       `Auth: default-credentials`. Pass it only to `devops` or `pr-reviewer`. Never pass it to
       another agent. Never write the PAT to a file, a commit, a plan, a handoff to another agent,
       or the final report. If no auth is known, ask one question.
   - Treat what comes back as the task text from here on.
   - Print the work-item number and title in one line, so the user can see what you resolved.
   - If `devops` cannot read it, stop and say so. Never guess what a work item contains, and
     never proceed on the number alone.
   - If the user gave both a reference and their own description, read the reference anyway, and
     say in one line where the two disagree. The user's words win on scope.
   - Give `planner` what the work item actually says, not a paraphrase of it. Carry its acceptance
     criteria into the plan as the acceptance criteria.
   - In the final report, name the work item as `<number> — <title>`. State which acceptance
     criteria the change satisfies and which it does not.
   - **Exception: a pull request to review.** When the reference is a pull-request URL, or the
     user asks to review a pull request, skip this step. The `review` workflow in pull-request
     mode reads the pull request itself, with a different set of fields.
3. Classify with the routing table below, using the resolved task text. A resolved work item is
   classified on what it asks for, not on the fact that it came from the work-item server — a defect report routes
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

Some tasks get no chain. The list of these tasks is in `CLAUDE-MAIN.md`, section "Orchestrate
multi-step work yourself". A git operation goes to the `git` agent, because it knows the team rules
for branch names, commit messages, and pull-request titles.

When you skip the chain, say so in one clause. Never start a chain when the task needs only one
agent.

### Model policy

Pass `model` on every `Agent` call. Default to these, and say in one line when you deviate.

| Step | Model | Why |
|---|---|---|
| `architect` | `opus` | Judgement. A wrong decision gives a wrong plan |
| `planner` | `sonnet` when the task touches 1 project and fewer than 3 files, `opus` otherwise | A small task needs little judgement. Estimate the size from the task text and the `architect` report |
| `pr-reviewer` (`review`, pull-request mode) | `sonnet` | The agent file holds the procedure. The reviewers that it starts do the judgement |
| implementer agents, fix pass | `sonnet` | The plan already holds the decisions, so the step is execution, not judgement |
| `tester` | `sonnet` | The test plan already names what to assert. Raise it to `opus` when its report says "Recommend `opus`", or when the tests must control concurrency or guard a published contract |
| `code-reviewer`, `security-reviewer`, `migration-reviewer` | `sonnet` | The agent file holds the checks. Raise it to `opus` by the rules in "Reviewer model" |
| `style-reviewer`, `devops`, `git`, `Explore`, `explore-web` | `haiku` | Rule matching, lookup, search, and flow summaries. The agent file holds the rules, so the step needs no judgement. Raise it to `sonnet` when the report misses a rule or a file that you can see. Raise `Explore` to `sonnet` for a flow over more than one project or more than about 5 steps |
| `docs-updater` | `sonnet` | It decides which document the change made wrong, and it writes new text |
| `general-purpose`, any other helper agent | `sonnet` | The task is open, so the agent file holds no rules for it |

The main session plans, decides, and resolves questions from the agents.

Raise any other step to `opus` when one of these is true:

- The task is cross-repository.
- The task touches a published contract.
- The user says the change is risky.

#### Reviewer model

- All three reviewers go to `opus` when one of these is true:
  - The diff is over about 300 lines or over 5 files.
  - The diff touches a published contract.
  - The task is cross-repository.
  - The user says the change is risky.
- `security-reviewer` also goes to `opus` when the diff changes authentication, authorization,
  crypto, or secret storage, when the diff changes a hook, an installer, an update script, or an MCP
  server entry, or when the task reports a vulnerability or a leaked secret.
- `migration-reviewer` also goes to `opus` when the migration drops or renames a column or a table,
  changes a column type, or moves data in a table that already holds data.

`orchestrate.md` and `pr-reviewer.md` hold the same text. Keep the two texts identical.

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

`shared-steps.md` holds the five shared steps, the browser check step, the fix pass, and the
system-wide impact check.

## The guards

A guard adds a reviewer to the review step. Decide each guard from the diff after the test step,
not from the plan. Why: the plan can miss a SQL file or a configuration change that the implementer
added.

- **The security guard** adds `security-reviewer` when the diff touches input handling,
  authorization, data access, file paths, configuration, secrets, crypto, or an outbound call. It
  also fires when the task reports a vulnerability or a leaked secret, or asks whether code is safe,
  or when an implementer report names `security-reviewer` as the next step.
- **The migration guard** adds `migration-reviewer` when the diff contains a migration, a schema
  change, or SQL. It also fires when an implementer report names `migration-reviewer` as the next
  step.

Print each guard that fired, and the reason in one clause, in the step line of the review step.
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
- Give a reviewer the diff base and the scope. Never paste the diff or the implementer summary.
- Name the sibling that the new code must match. Tell the implementer to copy the sibling pattern,
  or to use a different pattern in both the new code and the sibling. Never allow a new pattern in
  the new code only. Why: a helper class that no sibling uses gives the code two ways to do one
  thing.
- Put the files in the task scope in **Constraints**, and tell the agent to change no other file,
  except a sibling that it aligns by the rule above.

## After each step

Before each implementer or `tester` step, run `git status --porcelain` and keep the output. After
the step, run it again and compare. A file that changed outside the task scope is a finding,
unless the agent report names it as an aligned sibling. Send
it back to the agent before the next step. Why: a later agent once restored a file outside its task,
and the regression showed only in the next test run.

Then print exactly two lines:

```
Step <n> of <total> done: <agent> — <one-line outcome>
Next: <agent> — <one-line job>
```

Then check the compact gates below. When no gate applies, run the next step. Do not print the agent's full report between steps.

When you end a turn only to wait for a background agent, make this the exact last line of the
message:

```
Waiting for agents. Nothing needed from you now.
```

Why: the toast hook `notify.ps1` matches this line and shows no "Claude: done" toast for that turn.

## Compact gates

`/compact` clears the spent context and keeps a summary. Only the user can run it. You never run
it, and no agent can run it for the user.

This section is the only full copy of the compact rules. `CLAUDE-MAIN.md` and the
`strategic-compact` skill point here.

Check for a compact gate after each step, before you start the next step.

### The three gates

In time order:

1. **Gate A — the design is done.** After the last design step, and before the first implementer
   starts. The last design step is `planner` in `feature`, the reproduce step of `tester` in
   `bugfix`, and the baseline step of `tester` in `refactor`. Never put the gate between
   `architect` and `planner`, because the plan needs the design note.
2. **Gate B — the code is done.** After the first test step that follows the implementer, and
   after the browser check step when that step runs. Gate B comes before the first review step
   starts. The reviewers read the diff from disk, not from the context. A fix pass, its re-test,
   and a second review run never open gate B again.
3. **Gate C — the task is done.** After the final report, and before a new task starts in the same
   session.

The `test` workflow has no design step and no implementer. Only gate C applies to it.

### The three blocks

Never ask for a compact at these points. The next step needs the context that a compact drops.

1. In the middle of one stage.
2. Between a review step and its fix pass. The fix pass needs the findings in full.
3. Before the final report. The report needs every path, number, and caveat from the chain.

### How to decide

Ask for a compact at a gate when one of these is true. Otherwise continue and say nothing.

1. The `[StrategicCompact]` hook printed a message since the last gate. The hook reads the context
   size of this session from the status line file. When that file is old, it reads the transcript.
   It prints a message when the context reaches 15% of the window, and again at each further 10%.
2. The next stage works on a different area of the code. A different area means a different
   project or a different top-level folder than the last stage.

Agents read the files, not this session. So the number of files that a stage read does not tell
you the size of this context. Use the hook message.

### How to ask

Print these three lines, then stop and wait for the user.

```
Compact gate <A|B|C>: <gate name> — <the reason in one clause>
Run: /compact Keep: <the facts the next step needs, one line>
Then say "continue". I resume at step <n> of <total>.
```

The `Keep:` line is the focus text for `/compact`. Put the workflow name, whether the
workflow uses `shared-steps.md`, the plan decisions, the file paths, the acceptance criteria, and
the open findings in it. Leave out the search results and the file contents.

When the user says "continue" after gate A or gate B, read these files again with the Read tool.
Replace `~` with the `%USERPROFILE%` path.

1. `~/.claude/commands/orchestrate.md`, this file.
2. `~/.claude/orchestrate/<workflow>.md`, the file of the current workflow.
3. `~/.claude/orchestrate/shared-steps.md`, when the table in "Workflows" says so.

If a read fails, stop. Say so. Then restate the step line. Run the step. Why: a compact turns the
earlier reads into a summary, and a step must not run from memory.

After gate C, skip the re-read. The next task starts at Step 0, which reads the files of its own
workflow.

## Stop rules

Stop the chain and report, when:

- An implementer reports the task is blocked.
- A build or a test fails and the implementer could not fix it.
- A stage needs a second fix pass. See "The fix pass" in `shared-steps.md`. A reviewer that returns a
  blocking finding after the first fix pass means the chain is not converging.
- `tester` cannot reproduce the bug in the `bugfix` workflow. Do not fix a bug that no test or
  reproduction shows.
- The test counts after a refactor do not match the baseline, and the fix pass already ran once.
  This applies to the covering-test counts of the test step. It applies to the full-suite counts of
  the final suite run only when the baseline step of `refactor` recorded a full-suite baseline.
  Each set has its own baseline from the baseline step of `refactor`.
- The browser check fails again after one fix pass.
- The user interrupts.
- `architect` returned two viable options with a real trade-off. The choice is the user's. Print
  the recommendation and the alternatives, and stop. Do not pick.
- The fix needs a behaviour change for existing callers, and nobody asked for it. Describe the
  choice and stop.

Say which step stopped it and why, in one line.

## Final report

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

Commit
------
Branch: <branch name>
Commit message: <from the commit step>
Pull-request title: <from the commit step>
Committed: <commit hash | not committed — the user did not ask>

Verdict: <COMMITTED | READY TO COMMIT | NEEDS WORK | BLOCKED>
```

After the report, check gate C. End with one next action the user can do in under two minutes.

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
- Effort: the frontmatter `effort` field (`low` to `max`) and the `Agent` `effort` parameter
  (Claude Code v2.1.292 or later) set it. No team agent sets it.




