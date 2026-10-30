# Resolve a reference

Read this file in Step 0 of `orchestrate.md` when the task is a reference instead of a description.
A reference is an Azure DevOps URL, a pull-request URL, or a bare work-item number such as `32617`.

Run `devops` on it before anything else, and ask it for the title, the description, the acceptance
criteria, the state, the linked work items, and the linked pull requests.

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
- If `devops` cannot read it, stop and say so. Never guess what a work item contains, and never
  proceed on the number alone.
- If the user gave both a reference and their own description, read the reference anyway, and say
  in one line where the two disagree. The user's words win on scope.
- Give `planner` what the work item actually says, not a paraphrase of it. Carry its acceptance
  criteria into the plan as the acceptance criteria.
- In the final report, name the work item as `<number> — <title>`. State which acceptance criteria
  the change satisfies and which it does not.
- **Exception: a pull request to review.** When the reference is a pull-request URL, or the user
  asks to review a pull request, skip this step. The `review` workflow in pull-request mode reads
  the pull request itself, with a different set of fields.
