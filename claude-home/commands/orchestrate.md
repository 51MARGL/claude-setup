---
description: Run a fixed chain of agents over one task — plan, implement, test, review, update the docs, commit — with a handoff between each step and a state line after each step.
argument-hint: <design|feature|bugfix|test|refactor|review|custom> <description | pull-request URL or number>
---

# Orchestrate

Run a named agent chain over the task in `$ARGUMENTS`. You are the orchestrator. You do not write
the code yourself. Each step is one agent invocation.

## Step 0 — pick the workflow, then show the chain

1. Read the first word of `$ARGUMENTS`. If it names a workflow, use it. The rest is the task.
2. **If the task is a reference instead of a description, resolve it first.** A reference is a
   an Azure DevOps URL, a pull-request URL, or a bare work-item number such as `32617`. Run
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
4. Print the chosen workflow, the reason in one clause, and the chain as a numbered list with the
   model each step runs on.
5. Start immediately. Do not ask for permission to begin, unless the workflow is `custom` and the
   agent list is missing.

### Routing table

Match top to bottom. The first row that fits wins.

| The task | Workflow |
|---|---|
| Asks where something belongs, what it breaks, or which option to take | `design` |
| Is a pull-request URL, or asks to review a pull request by number | `review`, pull-request mode |
| Is only a reference: a work-item number, or a work-item URL | resolve it in step 2, then classify on the resolved text |
| Asks to add tests, fix a test, or find a flaky test, with no production change | `test` |
| Reports wrong behaviour: an error, a failing test, a wrong result, a vulnerability, a leaked secret | `bugfix` |
| Asks to review, check, or audit local work or code that already exists, including "is this safe" | `review`, local mode |
| Moves, renames, extracts, or deduplicates code with no behaviour change | `refactor` |
| Adds or changes behaviour, including a database schema, an entity, or a migration | `feature` |

Some tasks get no chain. The list of these tasks is in `CLAUDE-TEAM.md`, section "Orchestrate
multi-step work yourself". A git operation goes to the `git` agent, because it knows the team rules
for branch names, commit messages, and pull-request titles.

When you skip the chain, say so in one clause. Never start a chain when the task needs only one
agent.

### Model policy

Pass `model` on every `Agent` call. Default to these, and say in one line when you deviate.

| Step | Model | Why |
|---|---|---|
| `architect`, `planner` | `opus` | Judgement. A wrong decision gives a wrong plan |
| `pr-reviewer` (`review`, pull-request mode) | `opus` | It runs its own chain and merges the reviewer reports |
| implementer agents, fix pass | `sonnet` | The plan already holds the decisions, so the step is execution, not judgement |
| `tester` | `sonnet` | The test plan already names what to assert. Raise it to `opus` when its report says "Recommend `opus`", or when the tests must control concurrency or guard a published contract |
| `code-reviewer`, `security-reviewer`, `migration-reviewer` | `opus` | A missed defect costs more than the review |
| `style-reviewer`, `devops`, `git`, `Explore` | `haiku` | Rule checks, lookups, and searches. The agent file holds the rules, so the step needs no judgement. Raise it to `sonnet` when the report misses a rule or a file that you can see |
| `docs-updater` | `sonnet` | It decides which document the change made wrong, and it writes new text |
| `general-purpose`, any other helper agent | `sonnet` | The task is open, so the agent file holds no rules for it |

The main session runs on `opus`. It plans, decides, and resolves questions from the agents.

Raise a step to `opus` when the task is cross-repository, touches a published contract, or the
user says the change is risky. Use `sonnet` for a review step only when the diff is under about
50 lines and touches one file.

## Workflows

### design

1. `architect` — decide where the change belongs and what it breaks.
2. Stop. Print the recommendation and the open questions, and wait for the user to choose. A
   design decision is the user's, not yours.

### feature

0. `architect` — **run this by default.** These repositories are large, so placement is rarely
   obvious from the task text. Skip it only when both conditions are true:
   1. The task names the exact file or files.
   2. The change touches no published package, no message contract, no route, and no schema.

   When you skip it, name the two conditions in one line.
1. `planner` — produce the phased implementation plan.
2. `git` — the branch step. See [Shared steps](#shared-steps).
3. Implementer — `dotnet-developer`, `frontend-developer`, `powershell-developer`, or
   `container-developer`, chosen by the files the plan touches. If the plan touches both backend and frontend, run both implementers,
   backend first. When the change adds or changes an entity or a schema, tell the implementer to
   generate the migration through the repository's own workflow script.
4. `tester` — the test step. Give it the test plan from step 1.
5. `tester` — the browser check step. See [The browser check step](#the-browser-check-step--tester).
6. The review step: `style-reviewer` and `code-reviewer`, plus each reviewer that a guard adds. See
   [The guards](#the-guards). Run them in parallel, in one message.
7. Fix pass — see [The fix pass](#the-fix-pass).
8. `docs-updater` — the docs step.
9. `git` — the commit step.

### bugfix

Use this workflow for a vulnerability or a leaked secret too. The security guard then adds
`security-reviewer`.

1. `Explore` — find where the defect lives. Give it the symptom, not a guess at the cause. Set the breadth to `medium`.
2. `git` — the branch step.
3. `tester` — write a test that reproduces the bug. Run it, and show that it fails for the reason
   in the bug report.
4. Implementer — fix the bug. Give it the failing test as the definition of done.
5. `tester` — the test step. Run the test from step 3 and the suite of its test project.
6. `tester` — the browser check step. See [The browser check step](#the-browser-check-step--tester).
7. The review step: `code-reviewer`, plus each reviewer that a guard adds. Tell `code-reviewer` to
   confirm the fix and to look for the same defect elsewhere.
8. Fix pass — see [The fix pass](#the-fix-pass).
9. `docs-updater` — the docs step.
10. `git` — the commit step.

If the repository has no tests, `tester` reports that at step 3. Then give the implementer the
reproduction steps from the bug report instead.

### test

Use this workflow for test work with no change to production code: new tests for code that
already exists, a wrong test, or a flaky test.

1. `git` — the branch step.
2. `tester` — write or fix the tests, or find the cause of the flaky test. Tell it to edit test
   files only.
3. The review step: `code-reviewer` and `style-reviewer`, in parallel, in one message. Tell
   `code-reviewer` to check that each new test fails when the behaviour that it guards is reverted.
4. Fix pass — `tester` only.
5. `docs-updater` — the docs step.
6. `git` — the commit step.

If `tester` finds that production code is wrong, stop the chain. Print the failure, and offer the
`bugfix` workflow.

### refactor

0. `architect` — **run this by default.** Skip it only for a rename or an extraction that stays
   inside one project and changes no public surface. When you skip it, say why in one line.
1. `Explore` — map every caller and every dependency of the code to be changed. Set the breadth to `very thorough`.
2. `git` — the branch step.
3. `tester` — the baseline. Run the tests that cover the code from step 1, and record the counts.
   Add no test.
4. Implementer — make the change with no behaviour change.
5. `tester` — the test step. Run the same tests. The counts must match the baseline from step 3.
6. The review step: `style-reviewer` and `code-reviewer`, plus each reviewer that a guard adds. Run
   them in parallel, in one message.
7. Fix pass — see [The fix pass](#the-fix-pass).
8. `docs-updater` — the docs step.
9. `git` — the commit step.

### review

One workflow, two modes. The input selects the mode. The first word `pr` also selects this
workflow, in pull-request mode.

#### Pick the mode

Match top to bottom. The first row that fits wins.

| The input | Mode |
|---|---|
| A pull-request URL | pull-request mode |
| A bare number, and the user says "PR", "pull request", or the first word is `pr` | pull-request mode |
| A bare number with no other signal | ask one question: pull request or work item? |
| No reference, or the user says "local", "my changes", "my branch", "the diff", or names a path | local mode |

Print the mode and the reason in one line before the first step.

#### Pull-request mode

Review an Azure DevOps pull request. The `pr-reviewer` agent holds the full procedure. Do not
run the steps of that procedure yourself.

1. `pr-reviewer` (`opus`) — give it the pull-request URL or number, and tell it that a bare number
   is a pull-request id. Also give it `BaseUrl`, `Project`, and `Auth`, found by the rules in step 0,
   and `<scratchpad>/pr-<id>` as the worktree folder.
   Why an agent: the chain reads many files, and the agent keeps them out of this session.
2. If the report starts with `STOPPED`, print the reason and the question in it, and stop. When the
   user answers, start `pr-reviewer` again with the answer in the prompt.
3. Print the agent's report as the final report of this workflow. Do not use the normal final
   report. Keep every finding, path, and line number from it.

Never post a comment, never vote, and never change the pull request on the server. The vote is
the user's to cast.

#### Local mode

Review the work in the local repository.

1. Find the diff. Use the first rule that fits:
   - The user named a path, a branch, or a commit range: review that.
   - Otherwise: the uncommitted changes plus the commits on the current branch that are not on
     the default branch. Use `git merge-base HEAD origin/<default>` as the base.
   - If the diff is empty, stop and say so. Do not review the whole repository.
2. Print the base, the number of changed files, and the number of changed lines in one line.
3. Run in parallel, in one message:
   - `code-reviewer` — defects.
   - `style-reviewer` — repository conventions.
   - each reviewer that a guard adds. See [The guards](#the-guards).
   - `docs-updater` — report only. Tell it to list the documents that the diff made wrong, and
     to edit no file.

   When the user named a path and asked whether the code is safe, there is no diff. Review the
   files at that path instead. The security guard fires on the request itself.
4. Merge the reports into the normal final report. Remove duplicate findings, and keep the most
   severe rating of each one.

Local mode reports only. It runs no fix pass unless the user asks for one.

### custom

The task begins with a comma-separated agent list, then the description. Run them in that order.

```
/orchestrate custom "Explore,dotnet-developer,code-reviewer" fix the retry loop in the client
```

When the list names an implementer, add the four shared steps that the list does not name:

- the branch step, before the first implementer
- the test step, after the last implementer
- the docs step and the commit step, after the last agent in the list

Mark each added step as `(added)` in the printed chain. The user can remove it before step 1 starts.

## Shared steps

Every workflow that changes files runs the test step, the fix pass, the branch step, the docs step,
and the commit step. Never skip one to save time.

### The guards

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

### The test step — `tester`

Run it after an implementer, before the review step that follows.

1. Give it the files changed, the behaviours that the implementer report lists, and the test plan
   from `planner` when one exists.
2. Tell it to edit test files only.
3. Put its counts (passed, failed, skipped) in the step line.
4. If a test fails because of production code, send the failure to the implementer, then run the
   test step again. This counts as one fix pass.

If `planner` or `tester` reported that the repository has no tests, skip each later test step.
Say so in one line, and name the build as the only check in the final report.

Why: the implementers do not write or run tests. Without this step, nothing in the chain runs
them.

### The browser check step — `tester`

Run it after the test step, before the review step. It runs only in `feature` and `bugfix`.

It runs only when both conditions are true:

- The diff after the test step touches a file of one of these types, outside the test folders:
  - `.tsx`
  - `.jsx`
  - `.css`
  - `.scss`
  - `.sass`
  - `.less`
  - `.html`
- The repository runs as a standalone app with a dev server.

Decide from the diff, not from the plan.

1. Give `tester` these three inputs:
   - the acceptance criteria. In `bugfix`, give the reproduction steps from the bug report as the
     criteria.
   - the scratchpad path for screenshots
   - the dev-server script of the repository
2. Tell it to edit no file.
3. Put the result of each acceptance criterion in the step line.
4. If a check fails because of production code, send the failure to the implementer. Then run the
   test step again. Then run the browser check step again. This counts as one fix pass.
5. If `tester` reports `SKIPPED: login needed`, offer the user a check in their own browser with
   Claude in Chrome.

When a condition is false, skip the step. Say so in the step line.

Why: a unit test cannot show that a page renders and that the console has no error.

### The fix pass

A review step can return two kinds of findings. Route each finding to its owner:

- a defect in production code: the implementer that owns the stack
- a missing test, or a defect in a test: `tester`

Run the implementer first when both have findings. After the implementer changed code, run the test
step again. Also run the browser check step again when that step ran before.

When `security-reviewer` or `migration-reviewer` returned a blocking finding, run that reviewer
again after the fix pass. Tell it to confirm that each blocking finding is closed, and that the fix
opened nothing new.

Skip the fix pass when the review step returned no blocking finding. Say so in the step line.

### The branch step — `git`

Run it before the first implementer.

1. Run `git branch --show-current` yourself. Compare it with the default branch.
2. If the current branch is a work branch, skip the agent. Print the branch name in the step line.
3. If the current branch is the default branch, send `git`. Tell it to create a work branch and
   switch to it.
   - Give it the work-item number and title when step 0 resolved one.
   - Tell it to keep the uncommitted changes. It must not stash, reset, or discard them.

Why: a commit on the default branch cannot go into a pull request without extra history changes.

### The docs step — `docs-updater`

Run it after the last review step and its fix pass, before the commit step.

1. Give it the task, the files changed, and the diff base.
2. Tell it to edit documentation files only.
3. Add each file it changed to the "Files changed" list of the final report.

Run it always. It returns "no document is stale" when the diff makes no document wrong. That run
costs about 1 to 2 minutes on `sonnet`.

Why: you cannot tell from the handoffs alone which README, `CLAUDE.md`, or API description names
the changed code. The agent searches for them.

### The commit step — `git`

Run it last, and only when the chain ends with no blocking finding open.

1. Send `git` with the files changed, the work-item number and title, and the task.
2. Tell it to write the commit message and the pull-request title by its own rules.
3. Tell it what to do with them:
   - The user asked for a commit in the task, or during the chain: stage the changed files by
     name, and commit. Quote the user's own words in the prompt, as `User request: "<words>"`.
     Without the quote, `git` commits nothing.
   - The user did not ask: commit nothing. Return the message and the title only.
4. Put the branch, the commit message, the pull-request title, and the commit hash or "not
   committed" in the final report.

Never tell it to push, amend, or force-push unless the user asked for that exact operation. If a
commit hook fails, stop the chain and report the hook output. Never skip the hook.

Why: the user decides when work goes into the history. The agent still writes the message, so
the names follow the team rules.

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
- A reviewer gets the diff to review, never the implementer's own summary of it.
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

This section is the only full copy of the compact rules. `CLAUDE-TEAM.md` and the
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
   starts. The reviewers read the diff from disk, not from the
   context. A fix pass, its re-test, and a second review run never open gate B again.
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
   size of this session from the transcript. It prints a message when the context reaches 15% of
   the window, and again at each further 10%.
2. The next stage works on a different area of the code.

Agents read the files, not this session. So the number of files that a stage read does not tell
you the size of this context. Use the hook message.

### How to ask

Print these three lines, then stop and wait for the user.

```
Compact gate <A|B|C>: <gate name> — <the reason in one clause>
Run: /compact Keep: <the facts the next step needs, one line>
Then say "continue". I resume at step <n> of <total>.
```

The `Keep:` line is the focus text for `/compact`. Put the plan decisions, the file paths, the
acceptance criteria, and the open findings in it. Leave out the search results and the file
contents.

When the user says "continue", restate the step line first, then run the step.

## Stop rules

Stop the chain and report, when:

- An implementer reports the task is blocked.
- A build or a test fails and the implementer could not fix it.
- A reviewer returns a blocking finding and the fix pass already ran once. Two fix passes on the
  same finding means the chain is not converging.
- `tester` cannot reproduce the bug in the `bugfix` workflow. Do not fix a bug that no test or
  reproduction shows.
- The test counts after a refactor do not match the baseline, and the fix pass already ran once.
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
- Never skip a review step, the test step, the docs step, or the commit step to save time.
- Never report a step as done when its agent reported a failure.
- Keep every fact from an agent's report: a path, a number, a caveat.
- Effort is session-wide. You cannot set it per step. When the chain needs more than the session
  has, say so in one line before the first delegation, and let the user decide: "Effort is
  `medium`. This chain needs `high`. Run `/effort high` and start me again."




