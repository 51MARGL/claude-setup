# Team Claude Code setup

## Get the setup

1. Clone `<clone URL of this repository>` to a folder of your choice. Enter your credentials when Git asks.
   Git Credential Manager saves them.
2. Open PowerShell 7 in the clone. Keep the clone on the `master` branch.

## First install

Run this in PowerShell 7 in the clone:

```powershell
.\install.ps1
```

## Switches

| Switch | Effect |
|---|---|
| `-SkipStatusLine` | Do not install the statusline. |
| `-SkipMcp` | Do not add the MCP servers. |
| `-SkipOutputStyle` | Do not set `outputStyle`. |
| `-SkipAutoUpdate` | Do not add the `SessionStart` hook for automatic updates. The switch does not remove a hook that exists. See "Automatic updates". |
| `-UseSavedSwitches` | Use the switches of the last manual run. `update.ps1` uses this switch. You cannot combine it with a `-Skip` switch. |
| `-WhatIf` | Show the changes. Change nothing. |

There is no switch for `CLAUDE.md`. The installer copies the team rules to
`%USERPROFILE%\.claude\CLAUDE-TEAM.md`. It makes sure that `%USERPROFILE%\.claude\CLAUDE.md` holds
the import line `@~/.claude/CLAUDE-TEAM.md`, so Claude Code loads the team rules. `CLAUDE.md` is
yours. Put your own global instructions there. The installer never overwrites it.

After the install, restart Claude Code.

## Automatic updates

Claude Code runs `update.ps1` when a session starts. The hook is not `async`. Claude Code shows the
text "Checking for team Claude setup update..." while the hook runs. The first reply of Claude waits
for the hook. The wait is under 1 second when no check is due. The wait is up to about 2 to 3 minutes
when the script fetches and installs. The fetch timeout is 30 seconds, the install timeout is 120
seconds, and the hook timeout is 400 seconds.

The script does this:

1. It runs at most once every 60 minutes.
2. It runs only when the clone is on `master`, has no uncommitted changes, and has no untracked
   file in `claude-home`. It also needs a saved install state from a manual `install.ps1` run.
3. It fetches `origin/master`.
4. It fast-forwards the clone when `origin/master` has new commits.
5. It runs `install.ps1` with your saved switches when the clone has a commit that is not installed yet.
6. It writes a log to `%USERPROFILE%\.claude\team-setup\update.log`.
7. It shows the result message, for success or failure, in Claude Code and gives it to Claude as context.

The script only writes to `update.log` and shows no message when no check is due, when the clone is
not on `master`, when the clone has uncommitted changes or untracked files in `claude-home`, when
no install state exists, or when the fetch fails.

The script keeps the time of the last check in `%USERPROFILE%\.claude\team-setup\update-last-check.txt`.
The file holds an ISO 8601 time with an offset, for example `2026-09-30T14:05:00.0000000+02:00`.
The script reads this text. It does not use the write time of the file. A time without an offset
counts as local time.

To force an update at the next session start, use one of these:

- Edit the file to an older ISO time, for example `2026-09-01T08:00+02:00`.
- Delete the file.

The script counts the check as due, and writes a WARN to `update.log`, when the text is not an ISO
time (for example `10.02.2026`) or when the time is more than 5 minutes in the future.

The installer saves the switches of your last manual run. The next automatic update uses them. To
change them, run `install.ps1` again with the full set of switches that you want.

To stop the automatic updates, remove the `update.ps1` entry from `SessionStart` in
`%USERPROFILE%\.claude\settings.json` by hand. Then run `install.ps1` again with `-SkipAutoUpdate`,
so the installer does not add the hook again. The installer never removes a hook from your
`settings.json`.

If you move the clone to a new folder, the installed hook still points to the old path. Remove
the old `SessionStart` hook by hand, then run `install.ps1` from the new folder.

An automatic update overwrites the files that you edited in `%USERPROFILE%\.claude`. It makes no
backup. Edit the files in the clone instead.

## Security

Each push to `master` runs code on every machine that has the automatic update. The code runs at
the next session start, with the rights of the user. The update runs `install.ps1` and `update.ps1`
from the clone.

Protect `master` with these steps:

1. Set a branch policy on your Git server for `master` that requires a pull request.
2. Require one reviewer who is not the author.
3. Reset the votes on each push.
4. Allow no bypass and no force push, except for administrators.

Protect your machine with these steps:

1. Check that only your user can write to the clone folder. Other users must not have Modify rights on it.
2. Never set `http.sslVerify=false`. Install your organization's CA certificate instead.
3. Remove the `update.ps1` entry from `SessionStart` in `%USERPROFILE%\.claude\settings.json`, then run `install.ps1` with `-SkipAutoUpdate`. See "Automatic updates".

Before each merge, the update writes the list of new commits and the changed files to
`%USERPROFILE%\.claude\team-setup\update.log`. The message in Claude Code names the number of new
commits. It also names `install.ps1`, `update.ps1`, `claude-home/settings.json`,
`claude-home/CLAUDE-TEAM.md`, or `mcp/servers.json` when a new commit changes them.

## Use `/orchestrate` for bigger tasks

For any task that needs more than one agent or changes more than 2 files, start it with
`/orchestrate`. This is the main way to use this setup.

```text
/orchestrate feature add export to CSV on the order list
/orchestrate bugfix the retry loop in the HTTP client never stops
/orchestrate 32617
/orchestrate review https://dev.azure.com/<org>/<project>/_git/<repo>/pullrequest/1234
```

What `/orchestrate` does:

1. It picks a workflow from the first word, or from the task text when you give no workflow name.
2. It resolves a work-item number or an Azure DevOps URL through `devops` before it starts.
3. It runs a fixed chain of agents. Each agent gets a handoff from the previous one.
4. It stops at a compact gate and prints a `/compact Keep: ...` line. Run that line yourself, then
   tell Claude to continue. Only you can run `/compact`.
5. It ends with one final report.

The workflows:

| Workflow | Chain |
|---|---|
| `design` | `architect`, then it stops and waits for your decision |
| `feature` | `architect` (only when the task touches a contract, a schema, a route, a package, or more than 1 project) → `planner` → `git` branch → implementer → `tester` → `tester` browser check → `style-reviewer` + `code-reviewer` (+ guards) → fix pass → `docs-updater` → `tester` final suite run → `git` commit. Use it for schema changes and migrations too |
| `bugfix` | `Explore` → `git` branch → `tester` writes a failing test → implementer → `tester` → `tester` browser check → `code-reviewer` (+ guards) → fix pass → `docs-updater` → `tester` final suite run → `git` commit. Use it for a vulnerability or a leaked secret too |
| `test` | `git` branch → `tester` → `code-reviewer` + `style-reviewer` → fix pass by `tester` → `docs-updater` → `tester` final suite run → `git` commit. For test work with no production change |
| `refactor` | `architect` → `Explore` → `git` branch → `tester` baseline → implementer → `tester` → `style-reviewer` + `code-reviewer` (+ guards) → fix pass → `docs-updater` → `tester` final suite run → `git` commit |
| `review` | local diff, or a pull request through `pr-reviewer`, with the guards in both modes. Local mode also runs `docs-updater` in report-only mode |
| `custom` | your own comma-separated agent list, for example `/orchestrate custom "Explore,dotnet-developer,code-reviewer" <task>`. When the list names an implementer, `/orchestrate` adds the `git`, `tester`, `docs-updater`, and final suite run steps that the list does not name |

Two guards add `security-reviewer` and `migration-reviewer` to the review step. The conditions are
in `claude-home\commands\orchestrate.md`, section "The guards".

The implementer is `dotnet-developer`, `frontend-developer`, `powershell-developer`, or
`container-developer`, chosen by the files that the plan touches. The implementers do not write or
run tests. `tester` does all test work, and edits test files only.

The test step and the fix pass re-test run only the relevant tests. The final suite run runs the
full suite of each test project that the diff touches, and each test project that tests a project
that the diff touches. It runs each suite once, after the docs step and before the commit step.

The browser check step runs in `feature` and `bugfix` only. It runs when all three conditions are
true:

- The diff touches a UI file outside the test folders.
- The repository runs as a standalone app with a dev server.
- The acceptance criteria, or the reproduction steps in `bugfix`, name something visible on the
  page.

A UI file has one of these file types:

- `.tsx`
- `.jsx`
- `.css`
- `.scss`
- `.sass`
- `.less`
- `.html`

In the browser check step, `tester` drives a browser through the `playwright` MCP server. `tester`
edits no file.

The `git` branch step creates a work branch only when you are on the default branch. The `git`
commit step commits only when you asked for a commit. Otherwise it writes the commit message and
the pull-request title into the final report, and commits nothing.

Do not use `/orchestrate` for a task that needs no agent chain. Ask Claude directly instead. The
list of these tasks is in `claude-home\CLAUDE-TEAM.md`, section "Orchestrate multi-step work
yourself". Claude sends a git operation to the `git` agent. See the next section.

The full rules are in `claude-home\commands\orchestrate.md`.

## Git work

The `git` agent does local git work with fixed name rules that fit any repository. The rules are
in `claude-home\agents\git.md`.
The agent works in the repository that your request names, or in the current folder.
It starts a branch, stages and commits, updates a branch from the default branch, pushes, stashes,
and manages worktrees. It reads the default branch (for example `master` or `main`) from
`origin/HEAD`.

| Thing | Format |
|---|---|
| Branch for a work item | `item/<id>-<slug>` |
| Branch with no work item | `user/<login>/<slug>` |
| Commit message | `#<id> - <description>` |
| Pull-request title | `<id> - <description>` |

Example requests:

```text
start work on 1234
commit this for 1234
```

The agent writes the description in the language of the repository history. It checks the last 15
commit subjects. When you give only a work-item number, the agent asks you for the title.

The agent never adds a `Co-Authored-By:` line, a "Generated with" line, or another AI attribution
line to a commit message.

The agent never creates the pull request on the server. It returns the title, the source branch, and
the target branch, and you create the pull request. The agent never force-pushes.

## Mistakes log

Claude logs its own mistakes in `%USERPROFILE%\.claude\MISTAKES.md`. Each entry holds what
happened, the root cause, the consequence, and the rule that prevents a repeat. The newest entry
is first. The full rules are in the "Mistakes log" section of `claude-home\CLAUDE-TEAM.md`.

The file is yours:

- The installer does not ship `MISTAKES.md`, and does not overwrite or delete it.
- Claude creates the file at the first mistake.
- Each team member has their own file.

When the same root cause appears 3 times, Claude asks you whether to make it a rule. A team rule
goes into `claude-home\CLAUDE-TEAM.md` or an agent file in this repository, through a pull request. The
team reviews it there, and each member gets it on the next automatic update.

## What the installer does

1. It copies `claude-home\` into `%USERPROFILE%\.claude`.
2. It merges `settings.json` with your current file. Your own keys, such as `model`, stay. Your own
   hooks and permission rules stay, and the team entries are added once.
3. It merges the `env` block key by key. It adds only the keys that you do not have, and it keeps
   the values that you set.
4. It writes your own profile path into the hook paths and the statusline path.
5. It sets `outputStyle` to `AuDHD` in `settings.json` when the value there is missing or `default`.
   It keeps any other style that you set there. This is the user-level default. A style that you
   choose in `/config` for a project stays in that project's `.claude\settings.local.json` and
   takes precedence.
6. It never changes a hook that already exists in your `settings.json`.
7. It adds the MCP servers in `mcp\servers.json` with `claude mcp add --scope user`. An entry has
   the type `stdio` or `http`. The installer finds your existing servers in the `mcpServers` keys of
   `%USERPROFILE%\.claude.json`. When it cannot read that file, it runs `claude mcp get`. It never
   changes or removes a server that exists. A changed entry in `servers.json` therefore never
   reaches a machine that has the server. To get the new entry, run
   `claude mcp remove <name> --scope user`, then run `install.ps1` again. When `npx` is missing for
   a `stdio` server, the installer prints a Node.js 18 warning and still adds the server.
8. It records the path of each file that it installs in
   `%USERPROFILE%\.claude\team-setup\install-state.json`. It overwrites an installed file that
   differs from the team copy. It makes no backup. It deletes a file that an earlier install added
   and the repository no longer ships. It never deletes a file that it did not install.
9. It makes sure that `%USERPROFILE%\.claude\CLAUDE.md` holds the line `@~/.claude/CLAUDE-TEAM.md`.
   It does this at each install and each automatic update. It handles these cases:
   - No file: it creates the file with only the import line.
   - A file without the line: it adds the line at the top. The BOM and the line endings stay.
   - A UTF-32 file: it changes nothing and warns you. Add the line by hand.
   - A symlink: it writes to the target of the link.

## Contents

| Path | What it is |
|---|---|
| `update.ps1` | The automatic update. Claude Code runs it at session start. See "Automatic updates". |
| `claude-home\CLAUDE-TEAM.md` | Team global instructions. The installer copies them to `%USERPROFILE%\.claude\CLAUDE-TEAM.md`. They include one person's AuDHD and writing rules (ASD-STE100). Read them before you install them. |
| `claude-home\settings.json` | Permission deny and ask lists, the hooks, the statusline, the model, and the effort level. |
| `claude-home\agents\` | 16 agents: architect, planner, dotnet-developer, frontend-developer, powershell-developer, container-developer, tester, code-reviewer, style-reviewer, security-reviewer, migration-reviewer, docs-updater, devops, pr-reviewer, git, Explore. `architect` and `pr-reviewer` run on opus. `planner` runs on sonnet when the task touches 1 project and fewer than 3 files, and on opus otherwise. `code-reviewer`, `security-reviewer`, and `migration-reviewer` run on sonnet, and `/orchestrate` raises them to opus by the "Reviewer model" rules in `orchestrate.md`. The implementers, `tester`, and `docs-updater` run on sonnet. `devops`, `style-reviewer`, and `git` run on haiku. `Explore` runs on haiku too. It overrides the built-in `Explore` agent, so haiku is the default model of that agent. A caller can still pass another `model` value in the `Agent` call, and that value wins. `/orchestrate` raises `tester` to opus for concurrency tests, for published contracts, or when `tester` asks for it. `/orchestrate` sets the model of each agent that it calls. When you call any other agent yourself, name the model in your request. |
| `claude-home\commands\orchestrate.md` | The `/orchestrate` command. See the section above. |
| `claude-home\output-styles\audhd.md` | The AuDHD output style. The installer selects it for you when `settings.json` has no other style. You can also select it with `/config` → Output style. |
| `claude-home\skills\strategic-compact\` | The skill and the `UserPromptSubmit` and `PostToolUse` hooks that suggest `/compact` at 10% of the window, then at each further 10%. The hooks read the context size from the file that `statusline.ps1` writes. When that file is missing or older than 10 minutes, they read the transcript. Set `COMPACT_CONTEXT_PERCENT` and `COMPACT_CONTEXT_WINDOW` to change the values. |
| `claude-home\hooks\notify.ps1` | The hook that shows a Windows toast when Claude needs you. See the next section. |
| `claude-home\statusline.ps1` | The statusline script. It also writes the context size of the session for the strategic-compact hooks. |
| `mcp\servers.json` | User-scope MCP servers: `microsoft-learn` (http), `playwright` (stdio, `cmd /c npx -y @playwright/mcp@latest --headless --isolated --browser msedge --output-dir %TEMP%\playwright-mcp`), and `context7` (http, no key). See "MCP servers". |

## MCP servers

The installer adds three MCP servers at user scope. See step 7 of "What the installer does".

| Server | Type | Use |
|---|---|---|
| `microsoft-learn` | http | Microsoft and Azure documentation. |
| `playwright` | stdio | The browser check step of `tester`. It runs Microsoft Edge headless and isolated. |
| `context7` | http | Library documentation. It needs no key. |

The team settings deny 4 `playwright` tools: `browser_evaluate`, `browser_run_code_unsafe`,
`browser_file_upload`, and `browser_install`.

To use a personal Context7 API key, add the server again yourself with
`--header "Authorization: Bearer <key>"`. Never commit a key to this repository.

## Notifications

`notify.ps1` shows a Windows toast when Claude needs your input:

| Event | Toast title |
|---|---|
| A turn ends, `background_tasks` is empty, and the last message has no wait line (`Stop`) | "Claude: done" |
| A permission prompt appears (`Notification`) | "Claude: permission needed" |
| Claude asks for input in a dialog (`Notification`, `elicitation_dialog` or `elicitation_url_dialog`) | "Claude: input needed" |
| Claude asks a question with options (`PreToolUse`, `AskUserQuestion`) | "Claude: decision needed" |

The script shows no toast for other notifications, such as the idle prompt. It shows no toast for
subagents.

The `/orchestrate` command ends a turn with the line `Waiting for agents. Nothing needed from you
now.` when it waits for agents. That line suppresses the `Stop` toast.

Each toast body starts with the project folder name, for example `[my-repo]`, so you can tell the
sessions apart.

Limits:

1. The toast shows "Windows PowerShell" as the sender. The script uses Windows PowerShell 5.1 for
   the toast, because pwsh 7 cannot load the Windows toast API.
2. Focus Assist or Do Not Disturb hides the pop-up. The toast still goes to the notification center.
3. The script shows at most 1 toast every 5 seconds per session.
4. The hooks run in the background (`async`), so they do not slow Claude.
5. The `Stop` and `AskUserQuestion` toasts appear about 2 seconds after the event.
6. The permission and elicitation toasts appear about 5 to 7 seconds after the event. The script
   skips the toast when the session writes its transcript in that window. Claude then no longer
   waits for you.
7. A permission toast can still appear after you approve. This happens when the approved tool runs
   for more than 5 seconds with no transcript write.
8. The script shows no "Claude: done" toast while any background task runs. `background_tasks`
   lists background shell commands and background agents. A long-running background shell command,
   such as a dev server or a file watcher, blocks the toast until it stops. A background agent or
   build that ends is no problem. Claude then continues the session, and the next turn end shows
   the toast.

To stop the toasts, delete the three `notify.ps1` entries from `%USERPROFILE%\.claude\settings.json`.
You can also disable them in `/hooks`.

## Requirements

- Windows 10 or 11.
- PowerShell 7 (`pwsh`) on `PATH`. The hooks and the statusline run through `pwsh`.
- Windows PowerShell 5.1 (`powershell.exe`). Windows includes it. The toast needs it.
- Claude Code CLI (`claude`) on `PATH` for the MCP step.
- Node.js 18 or later (`npx` on `PATH`), for the `playwright` MCP server.
- Microsoft Edge, for the `playwright` MCP server.
- Network access to your Azure DevOps server, for the `devops` and `pr-reviewer` agents.
- Authentication for the `devops` agent. In the session, give a personal access token (PAT), the name of an environment variable that holds a PAT, or Windows integrated authentication. A PAT that you paste in the chat stays in the session transcripts under `%USERPROFILE%\.claude\projects`.