# feature

0. `architect` — run this only when the task touches a contract, a schema, a route, a package, or
   more than 1 project. When you skip it, say in one line that the task touches none of these.
1. `planner` — produce the phased implementation plan. Give it the path of `design-note.md` when
   step 0 ran.
2. The plan-confirm stop. See "The plan-confirm stop" in `orchestrate.md`.
3. `git` — the branch step. See "Shared steps" in `shared-steps.md`.
4. Implementer — `dotnet-developer`, `frontend-developer`, `powershell-developer`,
   `container-developer`, or `markdown-developer` (a Markdown file that is the deliverable),
   chosen by the files the plan touches. Run one implementer for each chunk file, in order. Run
   `git status` before and after each chunk. If the plan touches both backend and
   frontend, run both implementers, backend first. When the change adds or changes an entity or a
   schema, tell the implementer to generate the migration through the repository's own workflow
   script.
5. `tester` — the test step. Give it the test plan from step 1.
6. `tester` — the browser check step. See "The browser check step" in `shared-steps.md`.
7. The review step: `reviewer`, with each `Focus:` line that a guard adds. See "The guards" in
   `orchestrate.md`.
8. Fix pass — see "The fix pass" in `shared-steps.md`.
9. `docs-updater` — the docs step.
10. `tester` — the final suite run. See "The final suite run" in `shared-steps.md`.
11. `git` — the commit step.
