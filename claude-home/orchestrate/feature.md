# feature

0. `architect` — run this only when the task touches a contract, a schema, a route, a package, or
   more than 1 project. When you skip it, say in one line that the task touches none of these.
1. `planner` — produce the phased implementation plan.
2. `git` — the branch step. See "Shared steps" in `shared-steps.md`.
3. Implementer — `dotnet-developer`, `frontend-developer`, `powershell-developer`, or
   `container-developer`, chosen by the files the plan touches. If the plan touches both backend and
   frontend, run both implementers, backend first. When the change adds or changes an entity or a
   schema, tell the implementer to generate the migration through the repository's own workflow
   script.
4. `tester` — the test step. Give it the test plan from step 1.
5. `tester` — the browser check step. See "The browser check step" in `shared-steps.md`.
6. The review step: `style-reviewer` and `code-reviewer`, plus each reviewer that a guard adds. See
   "The guards" in `orchestrate.md`. Run them in parallel, in one message.
7. Fix pass — see "The fix pass" in `shared-steps.md`.
8. `docs-updater` — the docs step.
9. `tester` — the final suite run. See "The final suite run" in `shared-steps.md`.
10. `git` — the commit step.
