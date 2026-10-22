# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

The team Claude Code setup. `install.ps1` copies `claude-home\` into `%USERPROFILE%\.claude` on each
team member's machine. `update.ps1` runs at each session start (a `SessionStart` hook), fast-forwards
the clone from `origin/master`, and runs `install.ps1 -UseSavedSwitches`.

Each merge to `master` runs on every team machine at the next session start. Changes reach `master`
only through a pull request.

When a check stops the update, `update.ps1` shows the stop message once per 24 hours for each
reason. The reasons are: not on `master`, uncommitted changes, untracked files, `git-failed` (a git
command failed or timed out), `merge-failed`, and `install-failed`. It records the last message in
`%USERPROFILE%\.claude\team-setup\update-last-stop.json`. It deletes the file only when the update
succeeds.

## Commands

There is no build and no test suite. Use these checks:

```powershell
# Parse a script
$errors = $null; [System.Management.Automation.Language.Parser]::ParseFile("$PWD\install.ps1", [ref]$null, [ref]$errors); $errors

# Show what the installer would change, and change nothing
.\install.ps1 -WhatIf

# Install from this clone into your own %USERPROFILE%\.claude
.\install.ps1
```

`install.ps1` and `update.ps1` need PowerShell 7.2.

Your own `%USERPROFILE%\.claude` holds an installed copy. Edit the files in this repository, not
the installed copy. The next automatic update overwrites an edited installed file, with no backup.

## How the installer treats each file

- **Plain files in `claude-home\`**: copied. The installer records the installed paths in
  `%USERPROFILE%\.claude\team-setup\install-state.json`. When you delete a file
  or a whole folder from `claude-home\`, the installer deletes the installed copy too. The installer
  throws when `claude-home\` holds no file. It skips a saved path that is empty, is rooted, or
  contains `..` or `:`, and prints a warning.
- **`claude-home\settings.json`**: merged, not copied. The merge is additive:
  - `permissions.allow`, `permissions.deny`, and `permissions.ask`: team entries are added. A team
    entry that you delete from this file stays on every machine that has it. No retire list exists
    for permission entries, so an allow entry is a permanent grant on each machine. The allow entries
    let the main session read `~/.claude/commands/orchestrate.md`, `~/.claude/orchestrate/`, and
    `STE.md` with no prompt. The main session reads the two `orchestrate` paths again after a
    compact. Claude Code reads with no approval only inside the working directory and the
    additional directories. The deny entries guard the usual command form. They are not a security
    boundary around the program.
  - `env` and other top-level keys (`model`, `effortLevel`, ...): the installer adds a key only when
    the user does not have it. A changed or deleted value never reaches an existing install.
  - `hooks`: a hook has the identity `command` + `args`. A hook with new `args` or a new `matcher`
    is added as a second hook. An existing hook is never changed.
  - `statusLine`: replaced.
- **`mcp\servers.json`**: an entry has the type `stdio` or `http`. The installer adds it with
  `claude mcp add --scope user`. It never changes an existing server. A changed entry reaches a
  machine only after the user runs `claude mcp remove <name> --scope user` and `install.ps1` again.
- **Placeholders**: the installer replaces `{{CLAUDE_HOME}}` and `{{TEAM_SETUP_REPO}}` with real
  paths. Use them in every path in `settings.json`. The exception: a permission rule path uses `~/`
  (home-relative) and not a placeholder.
- **`CLAUDE-TEAM.md`**: copied. The user's own `%USERPROFILE%\.claude\CLAUDE.md` gets only the
  import line `@~/.claude/CLAUDE-TEAM.md`. `CLAUDE-TEAM.md` imports `STE.md` with the line
  `@~/.claude/STE.md`.
- **`STE.md`**: copied. It holds the full STE rules. The main session and each agent load it through
  the import in `CLAUDE-TEAM.md`. The `devops`, `git`, and `pr-reviewer` agents have
  `omitClaudeMd: true`, so they read `STE.md` themselves.
- **`CLAUDE-MAIN.md`**: copied. It holds the rules for the main session only. The hook
  `hooks\main-session-rules.ps1` (a `SessionStart` hook) prints it as context. A subagent gets no
  copy, because the hook exits when `agent_id` is set. The hook runs at `startup|resume|clear|compact`.
  When the file is missing or the read fails, the hook shows a message that the rules did not load.
- **`orchestrate\`**: copied. It holds one file for each `/orchestrate` workflow and
  `shared-steps.md`. Step 0 of `commands\orchestrate.md` reads only the files of the chosen
  workflow. The folder is not under `commands\`, because each file there is a slash command.

`update.ps1` names a file in its message when a new commit changes it (`$sensitivePaths`). The list
has 39 paths in 3 groups:

1. The files that run code: `install.ps1`, `update.ps1`, `claude-home/hooks/main-session-rules.ps1`,
   `claude-home/hooks/notify.ps1`, `claude-home/statusline.ps1`, and
   `claude-home/skills/strategic-compact/suggest-compact.ps1`.
2. The files that set permissions, hooks, tools, or the model: `claude-home/settings.json`,
   `mcp/servers.json`, and the 16 agent files `claude-home/agents/<name>.md`.
3. The rules that the main session loads or follows: `claude-home/CLAUDE-TEAM.md`,
   `claude-home/CLAUDE-MAIN.md`, `claude-home/STE.md`, `claude-home/commands/orchestrate.md`, the 8
   files `claude-home/orchestrate/<name>.md`, `claude-home/output-styles/audhd.md`,
   `claude-home/skills/mistakes-log/SKILL.md`, and `claude-home/skills/strategic-compact/SKILL.md`.

When you add a `.ps1` file, an agent file, or a rules file to `claude-home\`, add its path to
`$sensitivePaths`.

## Texts that must agree

Several files hold the same fact. When you change one, change the others in the same commit.

1. **Agent models**: the `model:` line of each agent file, the "Model policy" table in
   `claude-home\commands\orchestrate.md`, the table in `claude-home\agents\pr-reviewer.md`, and the
   `claude-home\agents\` row of the "Contents" table in `README.md`.
2. **The security guard and the migration guard**: `orchestrate.md` ("The guards") and
   `pr-reviewer.md` hold the same conditions. Keep the two texts identical.
3. **The list of tasks that need no agent chain**: only in `claude-home\CLAUDE-MAIN.md`
   ("Orchestrate multi-step work yourself"). `orchestrate.md` points to it. Do not copy it.
4. **Rules from `MISTAKES.md`**: the PowerShell alias ban, the line-endings rule, and the task-scope
   rule are in several agent files (`dotnet-developer`, `frontend-developer`,
   `powershell-developer`, `container-developer`, `tester`, `docs-updater`).
5. **The workflow chains**: the workflow files in `claude-home\orchestrate\` and the "Use
   `/orchestrate`" table in `README.md`.
6. **The compact threshold**: the percent in `README.md` (strategic-compact row),
   `claude-home\commands\orchestrate.md` (compact gates),
   `claude-home\skills\strategic-compact\SKILL.md`, and the `-Default` value in
   `suggest-compact.ps1`.
7. **The design-pattern rule and the report brevity rule**: the design-pattern rule is in
   `dotnet-developer`, `frontend-developer`, `powershell-developer`, and `container-developer`. The
   "Keep the report brief" text is in the report section of every agent file.
8. **The DTO doc-comment rule**: "Code style" item 6 in `claude-home\CLAUDE-TEAM.md`,
   `dotnet-developer.md`, `frontend-developer.md`, and `style-reviewer.md`.
9. **The test-run scopes**: `claude-home\orchestrate\shared-steps.md` (the test step, the fix pass,
   and the final suite run), `bugfix.md` (the `reproduce` scope) and `refactor.md` (the `baseline`
   scope) in the same folder, `tester.md`, and `README.md`. The system-wide impact criteria are
   only in `shared-steps.md` ("The system-wide impact check"). `tester.md` and `README.md` point
   to it. Do not copy them.
10. **The toast text** "Waiting for agents. Nothing needed from you now.": `orchestrate.md`,
    `README.md`, and `notify.ps1` (`$waitLine`).
11. **The `CLAUDE.md` read step**: the text "The root `CLAUDE.md` of the working directory is already
    in your context" is in `architect`, `planner`, `dotnet-developer`, `frontend-developer`,
    `powershell-developer`, `container-developer`, `tester`, `code-reviewer`, `style-reviewer`,
    `security-reviewer`, and `migration-reviewer`. Keep the 11 texts the same.
12. **The sensitive paths**: `$sensitivePaths` in `update.ps1`, the list in "How the installer treats
    each file" in this file, and the "Security" section of `README.md`. Keep the three lists the
    same.

## Writing rules for this repository

- Write agent files, commands, `README.md`, and commit messages in ASD-STE100 style, as
  `claude-home\STE.md` defines it. `STE.md` holds the full rules, because agents load it through the
  import in `CLAUDE-TEAM.md` and do not get the output style. `claude-home\output-styles\audhd.md` holds a worked example
  for each rule ("CT rule N").
- Keep CRLF line endings. The repository has no `.editorconfig`. On Windows, `sed -i` in Git Bash
  changes CRLF to LF, so use the Edit tool.
- An agent file starts with frontmatter: `name`, `description` (with the trigger words), `tools`
  when the agent is limited, and `model`.
- An agent file with the name of a built-in agent (`Explore`) overrides that built-in agent in every
  session.
- The `git` agent never adds a `Co-Authored-By:` line or any other AI attribution line to a commit
  message.
- `MISTAKES.md` belongs to each user and is not in this repository. A rule from it goes into
  `CLAUDE-TEAM.md`, `CLAUDE-MAIN.md`, or an agent file here, through a pull request.
