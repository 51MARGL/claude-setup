# Effort

Read this file before the first `Agent` call that can pass `effort`.

The Effort column in "Model policy" in `orchestrate.md` is the default. The frontmatter `effort`
field of each agent file sets it. The `effort` parameter of the `Agent` call overrides the
frontmatter value.

A change is **small** when all of these are true:

- It touches 1 project.
- It touches 2 files or fewer.
- The diff is about 100 lines or fewer.
- No guard fired.
- It touches no published contract.
- No step is raised to `opus`.

Before a diff exists, estimate the size from the task text and the plan.

- For a small change, pass `effort: "low"` in the `Agent` call. Do this for the implementer,
  `tester`, `reviewer`, `docs-updater`, and `Explore` with the breadth `quick`.
- For any other change, pass no `effort`. The frontmatter value applies.
- Never pass `low` to `architect`, to `planner`, or to a step raised to `opus`.
- Never pass `high`, `xhigh`, or `max`.