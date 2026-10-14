# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

The team Claude Code setup. `install.ps1` copies `claude-home\` into `%USERPROFILE%\.claude` on each
team member's machine. `update.ps1` runs at each session start (a `SessionStart` hook), fast-forwards
the clone from `origin/master`, and runs `install.ps1 -UseSavedSwitches`.

Each merge to `master` runs on every team machine at the next session start. Changes reach `master`
only through a pull request.

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

`install.ps1` needs PowerShell 7.0. `update.ps1` needs PowerShell 7.2.

Your own `%USERPROFILE%\.claude` holds an installed copy. Edit the files in this repository, not
the installed copy. The next automatic update overwrites an edited installed file, with no backup.

## How the installer treats each file

- **Plain files in `claude-home\`**: copied. The installer records the installed paths in
  `%USERPROFILE%\.claude\team-setup\install-state.json`. When you delete a file
  from `claude-home\`, the installer deletes the installed copy too.
- **`claude-home\settings.json`**: merged, not copied. The merge is additive:
  - `permissions.deny` and `permissions.ask`: team entries are added. A team entry that you delete
    from this file stays on every machine that has it.
  - `env` and other top-level keys (`model`, `effortLevel`, ...): the installer adds a key only when
    the user does not have it. A changed or deleted value never reaches an existing install.
  - `hooks`: a hook has the identity `command` + `args`. A hook with new `args` or a new `matcher`
    is added as a second hook. An existing hook is never changed.
  - `statusLine`: replaced.
- **Placeholders**: the installer replaces `{{CLAUDE_HOME}}` and `{{TEAM_SETUP_REPO}}` with real
  paths. Use them in every path in `settings.json`.
- **`CLAUDE-TEAM.md`**: copied. The user's own `%USERPROFILE%\.claude\CLAUDE.md` gets only the
  import line `@~/.claude/CLAUDE-TEAM.md`.

`update.ps1` names `install.ps1`, `update.ps1`, `claude-home/settings.json`, and
`claude-home/CLAUDE-TEAM.md` in its message when a new commit changes them (`$sensitivePaths`).

## Texts that must agree

Several files hold the same fact. When you change one, change the others in the same commit.

1. **Agent models**: the `model:` line of each agent file, the "Model policy" table in
   `claude-home\commands\orchestrate.md`, the table in `claude-home\agents\pr-reviewer.md`, and the
   `claude-home\agents\` row of the "Contents" table in `README.md`.
2. **The security guard and the migration guard**: `orchestrate.md` ("The guards") and
   `pr-reviewer.md` hold the same conditions. Keep the two texts identical.
3. **The list of tasks that need no agent chain**: only in `claude-home\CLAUDE-TEAM.md`
   ("Orchestrate multi-step work yourself"). `orchestrate.md` points to it. Do not copy it.
4. **Rules from `MISTAKES.md`**: the PowerShell alias ban, the line-endings rule, and the task-scope
   rule are in several agent files (`dotnet-developer`, `frontend-developer`,
   `powershell-developer`, `tester`, `docs-updater`).
5. **The workflow chains**: `orchestrate.md` and the "Use `/orchestrate`" table in `README.md`.

## Writing rules for this repository

- Write agent files, commands, `README.md`, and commit messages in ASD-STE100 style, as
  `claude-home\CLAUDE-TEAM.md` defines it.
- Keep CRLF line endings. The repository has no `.editorconfig`. On Windows, `sed -i` in Git Bash
  changes CRLF to LF, so use the Edit tool.
- An agent file starts with frontmatter: `name`, `description` (with the trigger words), `tools`
  when the agent is limited, and `model`.
- The `git` agent never adds a `Co-Authored-By:` line or any other AI attribution line to a commit
  message.
- `MISTAKES.md` belongs to each user and is not in this repository. A rule from it goes into
  `CLAUDE-TEAM.md` or an agent file here, through a pull request.
