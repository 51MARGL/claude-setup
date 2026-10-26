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

## Code search

1. Use the `codegraph_explore` tool first to find a symbol, its callers, its usages, or the structure of the code. If the tool is deferred, load it first with ToolSearch `select:mcp__codegraph__codegraph_explore`.
2. Use Grep and Glob in these conditions:
   - The search text is not a symbol name.
   - The file type is one that CodeGraph does not index, such as PowerShell, Markdown, JSON, and config files.
   - The repo has no CodeGraph index.
   - The `codegraph_explore` tool is missing.
3. Before each Grep on a code file, ask: is the target a symbol name? If yes, call `codegraph_explore` first.
4. A file name that is a class name is a symbol name. Call `codegraph_explore` for it, not `find`. Use Glob only to get the file names of a class, as item 5 says.
5. To get the source of a class, never query the class name alone. A class-name query can return other symbols and no file of the class. Do these steps:
   1. When the source is already in context, do not search.
   2. When the file names are not in context, get them with Glob `**/<ClassName>*`. Start the file-name part with the class name, not with a wildcard. This finds files of all types, such as `.cs`, `.ts`, and `.tsx`. When the repo uses kebab-case file names, such as `order-service.ts`, use the name with hyphens.
   3. Call `codegraph_explore` with all the file names in one query, such as `OrderService.cs OrderService.Init.cs`.
   4. If the result has no file whose name matches the class, the query was wrong. Do not read the result. Go back to step 2.
6. When a hook blocks a search, do what the hook says before any other search. Do not repeat the search with another tool.
7. A Read of a file that you already know is not a search. The code-search rules do not apply to it.

Why: CodeGraph returns a symbol and its callers in one call. Grep returns many lines that you must read, and these lines use more tokens.

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

