# Shared steps

Five shared steps: the branch step, the test step, the docs step, the final suite run, and the
commit step. The workflows `feature`, `bugfix`, `refactor`, and `test` run them, except that `test`
has no separate test step, because its `tester` step writes and runs the tests. The fix pass runs
only when the review step returns a blocking finding. Never skip a shared step in these four
workflows to save time.

## The system-wide impact check

The main session decides this check from the diff, like the guards. Run `git diff --name-only`. Read
the hunks that you need. Decide before the final suite run.

Before a diff exists, as in `refactor` step 3, the main session decides from the planned change. It
uses the `architect` and `Explore` output.

The check fires when the diff changes one of these:

- (a) a public member of a project that 2 or more other projects reference. A private change in
  such a project does not fire it.
- (b) a build or package file:
  - `Directory.Build.props`
  - `Directory.Packages.props`
  - `global.json`
  - a solution file
  - the dependencies in `package.json`
  - a lock file
- (c) startup, DI registration, or middleware that all endpoints use, such as:
  - `Program.cs`
  - `Startup.cs`
  - the DI extension methods
- (d) one of these:
  - a message contract
  - a public API contract
  - a database schema
- (e) shared test code

Print `full suite: <criterion>` or `relevant tests: no criterion fired` in the step block of the final
suite run.

This section is the only copy of the criteria. `tester.md` and `README.md` point here.

Why: the full suite costs the most tokens, and only a shared change can break a test that no earlier
step ran.

## The test step — `tester`

Run it after an implementer, before the review step that follows.

1. Give it the files changed, the behaviours that the implementer report lists, and the path of
   `plan-test.md` when `planner` made one.
2. Tell it to edit test files only.
3. Tell it to look for an existing test of each behaviour first, and to extend that test. Tell it
   to write one test for each behaviour in the list.
4. Tell it to run the new tests and the tests that cover the change. It never runs the full suite.
   Tell it to use a test filter and quiet switches. See `tester`, "Keep test output small".
5. Put its counts (passed, failed, skipped) in the step block.
6. If a test fails because of production code, send the failure to the implementer, then run the
   test step again. See [After each fix pass](#after-each-fix-pass).

If `planner` or `tester` reported that the repository has no tests, skip each later test step and
the final suite run. Say so in one line, and name the build as the only check in the final report.

If the diff changes only Markdown files, skip the test step, the browser check step, and the final
suite run. Print one line that says so. Run them when a test reads a changed Markdown file.

Why: the implementers do not write or run tests. Without this step, nothing in the chain runs
them.

## The browser check step — `tester`

Run it after the test step, before the review step. It runs only in `feature` and `bugfix`.

It runs only when all three conditions are true:

- The diff after the test step touches a file of one of these types, outside the test folders:
  - `.tsx`
  - `.jsx`
  - `.css`
  - `.scss`
  - `.sass`
  - `.less`
  - `.html`
- The repository runs as a standalone app: its `package.json` has a `dev` or `start` script.
- The acceptance criteria name something visible on the page. In `bugfix`, the reproduction steps
  name something visible on the page.

Decide from the diff, not from the plan.

1. Give `tester` these three inputs:
   - the acceptance criteria. In `bugfix`, give the reproduction steps from the bug report as the
     criteria.
   - the scratchpad path for screenshots
   - the dev-server script of the repository
2. Tell it to edit no file.
3. Put the result of each acceptance criterion in the step block.
4. If a check fails because of production code, send the failure to the implementer. Then run the
   test step again. Then run the browser check step again. See
   [After each fix pass](#after-each-fix-pass).
5. If `tester` reports `SKIPPED: login needed`, offer the user a check in their own browser with
   Claude in Chrome.

When a condition is false, skip the step. Say so in the step block.

Why: a unit test cannot show that a page renders and that the console has no error.

## The fix pass

A finding is **blocking** when it is one of these:

- a wrong result, a crash, data loss, or a broken contract
- a security finding rated Critical or High
- a break of a rule that the repository `CLAUDE.md` marks as required

Fix every blocking finding before the commit. Every other finding is non-blocking. Mark each finding `blocking` or `non-blocking`.

One fix pass is one fix-and-re-run of one stage. The stages are the test step, the browser check
step, the review step, and the final suite run.

Read the findings from `<scratchpad>\orchestrate\findings.md`, not from the context. Each handoff to
an implementer or `tester` in a fix pass names the path of `findings.md`, the round, and the finding
rows that the agent must fix. See "Before you ask about findings" in `orchestrate.md`.

A review step can return two kinds of findings. Route each finding to its owner:

- a defect in production code: the implementer that owns the stack
- a missing test, or a defect in a test: `tester`

Run the implementer first when both have findings. After the implementer changed code, run the test
step again, with only the relevant tests: the failed tests, the new tests, and the tests that cover
the fixed code. Tell `tester` to use a test filter and quiet switches. See `tester`, "Keep test output
small". Never run the full suite in a fix pass. Also run the browser check step again when
that step ran before.

When the review step returned a blocking finding, run `reviewer` again in `VERIFY` mode on the fix
diff. Give it the path of `findings.md`, the round, and the rows of the blocking findings. It
confirms that each one is closed and that the fix opened nothing new. Update the status of each
finding in `findings.md`.

Skip the fix pass when the review step returned no blocking finding. Say so in the step block. The
final report takes each non-blocking finding from `findings.md`.

### After each fix pass

After the fix pass, its re-test, and its `VERIFY` run, check these conditions:

- A blocking finding is still open.
- The `VERIFY` run found a new blocking finding.
- A test still fails because of production code.
- The browser check step fails again.
- In `refactor`, the test counts do not match the baseline. This applies to the covering-test
  counts of the test step. It applies to the full-suite counts of the final suite run only when the
  baseline step of `refactor` recorded a full-suite baseline. Each set has its own baseline from the
  baseline step of `refactor`.

After the final suite run, the `HUNT` pass on the new diff takes the place of the `VERIFY` run.

When one condition is true, do these steps in order:

1. Write the new round to `findings.md`. See "Before you ask about findings" in `orchestrate.md`.
2. Print the findings table.
3. Ask the user with AskUserQuestion: run another fix pass, or stop the chain. Put the open
   findings into the question. See "Put the items into the question" in `CLAUDE-MAIN.md`.

Never start another fix pass without the answer of the user. The number of fix passes has no
limit. When the user chooses to stop, stop the chain. See "Stop rules" in `orchestrate.md`.

## The final suite run — `tester`

Run it at most once, at the end of the chain. Run it after the review step, the fix pass, and the docs
step, and before the commit step. It runs also when no fix pass ran. It does not run when the diff
changes only Markdown files. See [The test step](#the-test-step--tester).

1. Decide by [The system-wide impact check](#the-system-wide-impact-check). Use the first case that
   fits:
   - In `refactor`, step 3 recorded a full-suite baseline: tell `tester` to run the full suite. Name the full-suite baseline from step 3 as the reason.
   - The check fired: tell `tester` to run the full suite of each test project that the diff
     touches. Also tell it to run the full suite of each test project that tests a project that the
     diff touches.
   - Code changed after the last test step: tell `tester` to run the relevant tests again. Give it
     the union of the scopes of the earlier test steps.
   - Otherwise: skip the run. Print one line that gives the reason.

   In the `test` workflow, the `tester` step 2 and the fix pass count as test steps, and a test file
   counts as code.
2. Tell it to edit no file.
3. Put its counts (passed, failed, skipped) in the step block.
4. If the suite fails because of production code, do these steps in order:
   - Send the failure to the implementer.
   - Run the test step on the failed tests.
   - Run one `reviewer` pass in `HUNT` mode on the new diff only.
   - Run the final suite run again.

   See [After each fix pass](#after-each-fix-pass).
5. In the `test` workflow, a failure caused by production code stops the chain. Print the failure,
   and offer the `bugfix` workflow.

If `planner` or `tester` reported that the repository has no tests, skip this step.

Why: the test step and the fix pass run only the relevant tests. The full suite finds a break in a
test that no earlier step ran, and only a system-wide change can cause that break. Other changes need
at most one more run of the relevant tests.

## The branch step — `git`

Run it before the first implementer.

1. Run `git branch --show-current` yourself. Compare it with the default branch from
   `git symbolic-ref --short refs/remotes/origin/HEAD`.
2. If the current branch is a work branch, skip the agent. Print the branch name in the step block.
3. If the current branch is the default branch, send `git`. Tell it to create a work branch and
   switch to it.
   - Give it the work-item number and title when step 0 resolved one.
   - Tell it to keep the uncommitted changes. It must not stash, reset, or discard them.

Why: a commit on the default branch cannot go into a pull request without extra history changes.

## The docs step — `docs-updater`

Run it after the last review step and its fix pass, before the commit step.

1. Give it the task, the files changed, and the diff base.
2. Tell it to edit documentation files only.
3. Add each file it changed to the "Files changed" list of the final report.

Run it always. It returns "no document is stale" when the diff makes no document wrong.

Why: you cannot tell from the handoffs alone which README, `CLAUDE.md`, or API description names
the changed code. The agent searches for them.

## The commit step — `git`

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
