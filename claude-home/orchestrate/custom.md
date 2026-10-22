# custom

The task begins with a comma-separated agent list, then the description. Run them in that order.

```
/orchestrate custom "Explore,dotnet-developer,code-reviewer" fix the retry loop in the client
```

When the list names an implementer, add the five shared steps that the list does not name:

- the branch step, before the first implementer
- the test step, after the last implementer
- the docs step, the final suite run, and the commit step, after the last agent in the list, in
  that order

Mark each added step as `(added)` in the printed chain. The user can remove it before step 1 starts.
