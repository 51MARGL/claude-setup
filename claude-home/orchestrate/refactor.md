# refactor

0. `architect` — **run this by default.** Skip it only for a rename or an extraction that stays
   inside one project and changes no public surface. When you skip it, say why in one line.
1. `Explore` — map every caller and every dependency of the code to be changed. Set the breadth to
   `very thorough`.
2. `git` — the branch step.
3. `tester` — the baseline scope. Add no test. Record two sets of counts:
   - the counts of the tests that cover the code from step 1
   - the counts of the full suite of each test project from the scope in "The final suite run" in
     `shared-steps.md`. Record them only when "The system-wide impact check" in `shared-steps.md`
     fires on the planned change. No diff exists yet, so decide from the `architect` and `Explore`
     output.
4. `planner` — plan the change. Give it the path of `design-note.md`, the `Explore` caller map, and the
   baseline counts from step 3.
5. The plan-confirm stop. See "The plan-confirm stop" in `orchestrate.md`.
6. Implementer — make the change with no behaviour change. Run one implementer for each chunk
   file, in order. Run `git status` before and after each chunk.
7. `tester` — the test step. Run the covering tests from step 3. The counts must match the
   covering-test baseline.
8. The review step: `reviewer`, with each `Focus:` line that a guard adds. See "The guards" in
   `orchestrate.md`.
9. Fix pass — see "The fix pass" in `shared-steps.md`.
10. `docs-updater` — the docs step.
11. `tester` — the final suite run. See "The final suite run" in `shared-steps.md`. Its
   counts must match the full-suite baseline from step 3. When step 3 recorded a full-suite
   baseline, run the full suite, also when the check does not fire on the diff. Otherwise compare
   the counts with the covering-test baseline. When the diff fires the impact check but step 3
   recorded no full-suite counts, run the full suite. Write "no baseline" in the final report.
12. `git` — the commit step.
