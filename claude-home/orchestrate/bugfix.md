# bugfix

Use this workflow for a vulnerability or a leaked secret too. The security guard then adds
`Focus: security`.

1. `Explore` — find where the defect lives. Give it the symptom, not a guess at the cause. Set the
   breadth to `medium`.
2. `git` — the branch step.
3. `tester` — the reproduce scope. Write a test that reproduces the bug. Run only that test, and
   show that it fails for the reason in the bug report.
4. `planner` — plan the fix. Give it the `Explore` result and the failing test. The plan names the
   cause at `path:line`, the files in scope, and what is out of scope.
5. The plan-confirm stop. See "The plan-confirm stop" in `orchestrate.md`.
6. Implementer — fix the bug. Give it the failing test as the definition of done.
7. `tester` — the test step. Run the test from step 3 and the tests that cover the change.
8. `tester` — the browser check step. See "The browser check step" in `shared-steps.md`.
9. The review step: `reviewer`, with each `Focus:` line that a guard adds. Tell it to confirm the
   fix and to look for the same defect elsewhere.
10. Fix pass — see "The fix pass" in `shared-steps.md`.
11. `docs-updater` — the docs step.
12. `tester` — the final suite run. See "The final suite run" in `shared-steps.md`.
13. `git` — the commit step.

If the repository has no tests, `tester` reports that at step 3. Then give `planner` and the
implementer the reproduction steps from the bug report instead.
