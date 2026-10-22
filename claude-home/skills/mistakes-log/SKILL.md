---
name: mistakes-log
description: Use when you write an entry in ~/.claude/MISTAKES.md.
---

# Mistakes log

The file `~/.claude/MISTAKES.md` is the user's own. The team installer does not ship it and does
not overwrite it. Each team member has their own file.

Why: a log turns "that area is flaky" into a count of one root cause. A root cause that repeats
becomes a rule for the whole team.

## The format

If the file does not exist, create it with the heading `# Mistakes`. Put the newest entry first,
directly below the heading.

```markdown
## <yyyy-MM-dd> — <short title>
- Repository: <repository name, or "all">
- Area: <agent, workflow, file, or tool>
- What happened: <the observed result, and the expected result>
- Root cause: <the real cause, not the symptom>
- Consequence: <what broke, and what it cost>
- Prevention: <the rule that stops a repeat>
- Same root cause as: <the dates of the earlier entries, or "none">
```

## When a mistake repeats, ask the user

1. Before you write an entry, search for earlier entries with the same root cause. List their
   dates in `Same root cause as`.
2. When the new entry is the third entry with the same root cause, stop and ask the user one
   question: `<root cause> is in MISTAKES.md 3 times. Make it a rule?`
3. In the same message, give the rule text and the target file:
   - A team rule goes into `claude-home/CLAUDE-TEAM.md`, `claude-home/CLAUDE-MAIN.md`, or into an agent file in the
     `claude-setup` repository. It goes through a pull request, so the team reviews it.
     Each member gets it on the next update.
   - A rule for one repository goes into the `CLAUDE.md` of that repository, through its own
     pull request.
4. Never write the rule into a `CLAUDE.md` or an agent file before the user says yes.
5. Never write the rule into `~/.claude/CLAUDE.md`. Why: that file is personal, and
   the rule does not reach the team.

After the answer of the user:

- Yes: write the change in the target repository. Add `- Graduated: <target file>, <date>` to
  each entry with that root cause. Keep the entries. They are the evidence for the rule.
- No: add `- Rule declined: <date>` to the newest entry. Ask again only after 2 more entries with
  that root cause.
