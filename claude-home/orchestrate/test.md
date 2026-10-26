# test

Use this workflow for test work with no change to production code: new tests for code that
already exists, a wrong test, or a flaky test.

1. `git` — the branch step.
2. `tester` — write or fix the tests, or find the cause of the flaky test. Tell it to edit test
   files only.
3. The review step: `reviewer`. Tell it to check that each new test fails when the behaviour that
   it guards is reverted.
4. Fix pass — `tester` only.
5. `docs-updater` — the docs step.
6. `tester` — the final suite run. See "The final suite run" in `shared-steps.md`.
7. `git` — the commit step.

If `tester` finds that production code is wrong, stop the chain. Print the failure, and offer the
`bugfix` workflow.

Gate A does not apply, because the workflow has no design step. Gate B applies only after the
re-test of a fix pass. Gate C and gate D apply as in `orchestrate.md`. See "Compact gates" in
`orchestrate.md`.
