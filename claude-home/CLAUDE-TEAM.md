# I have AuDHD (autism + ADHD)

I read and act on output differently. ADHD needs the next action up front and nothing held
in working memory. Autism needs literal language, consistent structure, and the reason
behind each decision. When they conflict: be brief on the surface, explicit underneath.

The AuDHD output style (`~/.claude/output-styles/audhd.md`) holds the reading rules, the output
rules, the exceptions, and the pre-send check.

@~/.claude/STE.md

## Work item effort

Write every effort value in man-days (MD). 1 MD equals 8 hours. Never write effort in hours.

Example: 3.2 hours of work is 0.4 MD. Write 0.4 and not 3.2.

Why: the team writes effort in MD in all effort fields.

## Code style

These apply whenever you write or edit code.

1. Do not write comments. Default to zero comments, except items 3 and 6. The code itself must explain
   what it does.
2. Code must be self-explanatory. Use clear names for variables, functions, and types so
   the code reads without needing a comment to decode it. If you feel a comment is needed,
   rename or extract instead.
3. The other allowed exception: a genuinely confusing place where the code cannot show the
   *why* — a workaround for an external bug, a non-obvious constraint, a deliberate
   deviation that looks wrong. One short line, and only there. Delete any comment that
   restates the next line.
4. Never mention bug numbers, ticket IDs, work-item numbers, PR numbers, issue links,
   commit hashes, or my name in code or comments. Write the reason itself, not a pointer to
   a tracker.

   Bad: `// Workaround for BUG-4821`
   Good: `// The API returns 200 with an empty body when the record is locked.`
5. Follow the project's `.editorconfig`. Match its indent style, indent size, line
   endings, charset, and trailing-whitespace/newline rules. If no `.editorconfig` exists,
   match the surrounding file.
6. A new DTO, request model, or response model gets a brief doc comment on each public property.
   Write one sentence that says what the value means, and its unit, format, or allowed values when
   it has one. The class gets a comment only when a sibling class has one. An existing contract
   type that gets a new member gets a doc comment on that member when a sibling member has one.
   Write the comment in the language of the sibling comments. A comment that only repeats the
   member name is a finding.

