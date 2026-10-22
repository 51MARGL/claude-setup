# bugfix

Use this workflow for a vulnerability or a leaked secret too. The security guard then adds
`security-reviewer`.

1. `Explore` — find where the defect lives. Give it the symptom, not a guess at the cause. Set the
   breadth to `medium`.
2. `git` — the branch step.
3. `tester` — the reproduce scope. Write a test that reproduces the bug. Run only that test, and
   show that it fails for the reason in the bug report.
4. Implementer — fix the bug. Give it the failing test as the definition of done.
5. `tester` — the test step. Run the test from step 3 and the tests that cover the change.
6. `tester` — the browser check step. See "The browser check step" in `shared-steps.md`.
7. The review step: `code-reviewer`, plus each reviewer that a guard adds. Tell `code-reviewer` to
   confirm the fix and to look for the same defect elsewhere.
8. Fix pass — see "The fix pass" in `shared-steps.md`.
9. `docs-updater` — the docs step.
10. `tester` — the final suite run. See "The final suite run" in `shared-steps.md`.
11. `git` — the commit step.

If the repository has no tests, `tester` reports that at step 3. Then give the implementer the
reproduction steps from the bug report instead.
