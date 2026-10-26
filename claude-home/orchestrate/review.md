# review

One workflow, two modes. The input selects the mode.

## Pick the mode

Match top to bottom. The first row that fits wins.

| The input | Mode |
|---|---|
| A pull-request URL | pull-request mode |
| A bare number, and the user says "PR" or "pull request" | pull-request mode |
| A bare number with no other signal | ask one question: pull request or work item? |
| No reference, or the user says "local", "my changes", "my branch", "the diff", or names a path | local mode |

Print the mode and the reason in one line before the first step.

## Pull-request mode

Review an Azure DevOps pull request. The `pr-reviewer` agent holds the full procedure. Do not
run the steps of that procedure yourself.

1. `pr-reviewer` — give it the pull-request URL or number, and tell it that a bare number
   is a pull-request id. Also give it `BaseUrl`, `Project`, and `Auth`, found by the rules in step 0
   of `orchestrate.md`, and `<scratchpad>/pr-<id>` as the worktree folder.
   Why an agent: the chain reads many files, and the agent keeps them out of this session.
2. If the report starts with `STOPPED`, print the reason and the question in it, and stop. When the
   user answers, start `pr-reviewer` again with the answer in the prompt.
3. Print the agent's report as the final report of this workflow. Do not use the normal final
   report. Keep every finding, path, and line number from it.

Never post a comment, never vote, and never change the pull request on the server. The vote is
the user's to cast.

## Local mode

Review the work in the local repository.

1. Find the diff. Use the first rule that fits:
   - The user named a path, a branch, or a commit range: review that.
   - Otherwise: the uncommitted changes plus the commits on the current branch that are not on
     the default branch. Get the default branch from
     `git symbolic-ref --short refs/remotes/origin/HEAD`. Use `git merge-base HEAD <default>` as the
     base.
   - If the diff is empty, stop and say so. Do not review the whole repository.
2. Print the base, the number of changed files, and the number of changed lines in one line.
3. Run in parallel, in one message:
   - `reviewer` — in `HUNT` mode, with each `Focus:` line that a guard adds. See "The guards" in
     `orchestrate.md`.
   - `docs-updater` — report only. Tell it to list the documents that the diff made wrong, and
     to edit no file.

   When the user named a path and asked whether the code is safe, there is no diff. Review the
   files at that path instead. The security guard fires on the request itself.
4. Merge the reports of `reviewer` and `docs-updater` into the normal final report. Remove duplicate findings, and keep the most
   severe rating of each one.

Local mode reports only. It runs no fix pass unless the user asks for one.
When the user asks for a fix pass, read `~/.claude/orchestrate/shared-steps.md` first. If the read
fails, stop and say so.
