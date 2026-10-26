# Team Claude Code setup

## Get the setup

1. Clone `<clone URL of this repository>` to a folder of your choice. Enter your credentials when Git asks.
   Git Credential Manager saves them.
2. Open PowerShell 7.2 or later in the clone. Keep the clone on the `master` branch.

## First install

Run this in PowerShell 7.2 or later in the clone:

```powershell
.\install.ps1
```

## Switches

| Switch | Effect |
|---|---|
| `-SkipStatusLine` | Do not install the statusline. |
| `-SkipMcp` | Do not add the MCP servers and do not install CodeGraph. |
| `-SkipOutputStyle` | Do not set `outputStyle`. |
| `-SkipAutoUpdate` | Do not add the `update.ps1` `SessionStart` hook for automatic updates. The installer still adds the `main-session-rules.ps1` `SessionStart` hook. The switch does not remove a hook that exists. See "Automatic updates". |
| `-UseSavedSwitches` | Use the switches of the last manual run. `update.ps1` uses this switch. You cannot combine it with a `-Skip` switch. |
| `-WhatIf` | Show the changes. Change nothing. |

There is no switch for `CLAUDE.md`. The installer copies the team rules to
`%USERPROFILE%\.claude\CLAUDE-TEAM.md`. It makes sure that `%USERPROFILE%\.claude\CLAUDE.md` holds
the import line `@~/.claude/CLAUDE-TEAM.md`, so Claude Code loads the team rules. `CLAUDE.md` is
yours. Put your own global instructions there. The installer never overwrites it.

After the install, restart Claude Code.

## Automatic updates

Claude Code runs `update.ps1` when a session starts. The hook is not `async`. Claude Code shows the
text "Checking for team Claude setup update and CodeGraph..." while the hook runs. The first reply of Claude waits
for the hook. The wait is under 1 second when no check is due. The wait is up to about 2 to 3 minutes
when the script fetches and installs. The fetch timeout is 30 seconds, the install timeout is 120
seconds, and the hook timeout is 400 seconds.

The script does this:

1. It runs at most once every 60 minutes.
2. It runs only when the clone is on `master`, has no uncommitted changes, and has no untracked
   file in `claude-home`. It also needs a saved install state from a manual `install.ps1` run.
3. It fetches `origin/master`. When the fetch fails or times out, the update stops with the
   `git-failed` message. A failed or timed-out `git rev-list` or `git rev-parse` stops it the same
   way. `install.ps1` does not run in these cases.
4. It fast-forwards the clone when `origin/master` has new commits. When the fast-forward times
   out, the update stops with the `merge-failed` message. `install.ps1` does not run in this case.
5. It runs `install.ps1` with your saved switches when the clone has a commit that is not installed yet.
6. It writes a log to `%USERPROFILE%\.claude\team-setup\update.log`.
7. It shows the result message, for success or failure, in Claude Code. It does not give the message to Claude.

The script writes only to `update.log` and shows no message when no check is due, or when no install
state exists.

When a check stops the update, the script shows the stop message once per 24 hours for each reason.
The reasons are: the clone is not on `master`, the clone has uncommitted changes, the clone has
untracked files in `claude-home`, a git command failed or timed out, the fast-forward failed, and
`install.ps1` failed. The script records the last stop message in
`%USERPROFILE%\.claude\team-setup\update-last-stop.json`. It deletes this file only when the update
succeeds.

The automatic update installs CodeGraph when `codegraph` is not on `PATH` and `-SkipMcp` is off. It
runs `npm i -g @colbymchenry/codegraph@latest` with a timeout of 180 s. It tries once per 24 hours
and records the time in `%USERPROFILE%\.claude\team-setup\codegraph-install-last-try.txt`. It deletes
the file when CodeGraph is installed. A second session that starts at the same time skips the
install. After a successful install, the message is "The update installed CodeGraph <version>.
Restart Claude Code to use the codegraph MCP server and the repo index." When the install fails, the
message is "CodeGraph failed to install", with the npm command, the restart request, and the path of
`update.log`. When `npm` is missing, the message shows the npm command only. When `codegraph.cmd` is
in the npm prefix but `package.json` has no readable version, the install is incomplete and the
update installs again (once per 24 hours).

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

Each session start can also run `npm i -g @colbymchenry/codegraph@latest` with no prompt, when
`codegraph` is not installed. npm gets the package from the public registry and runs the package
install scripts. The script runs npm in `%USERPROFILE%\.claude\team-setup` and removes the
`ANTHROPIC_*` and `CLAUDE_CODE_*` variables from the environment of npm. This is defence in depth
only. The install scripts run as the user and can read user files, such as
`%USERPROFILE%\.claude\.credentials.json`. Run `install.ps1` with `-SkipMcp` to turn this off.

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
commits. It also names a file when a new commit changes it. The message can name these files:

1. The files that run code: `install.ps1`, `update.ps1`, `claude-home/hooks/main-session-rules.ps1`,
   `claude-home/hooks/notify.ps1`, `claude-home/hooks/codegraph-init.ps1`, `claude-home/hooks/codegraph-search-guard.ps1`,
   `claude-home/statusline.ps1`,
   and `claude-home/skills/strategic-compact/suggest-compact.ps1`.
2. The files that set permissions, hooks, tools, or the model: `claude-home/settings.json`,
   `mcp/servers.json`, and the 17 agent files `claude-home/agents/<name>.md`.
3. The rules that the main session loads or follows: `claude-home/CLAUDE-TEAM.md`,
   `claude-home/CLAUDE-MAIN.md`, `claude-home/STE.md`, `claude-home/commands/orchestrate.md`, the 8
   files `claude-home/orchestrate/<name>.md`, `claude-home/output-styles/audhd.md`,
   `claude-home/skills/mistakes-log/SKILL.md`, and `claude-home/skills/strategic-compact/SKILL.md`.

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
| `custom` | your own comma-separated agent list, for example `/orchestrate custom "Explore,dotnet-developer,code-reviewer" <task>`. When the list names an implementer, `/orchestrate` adds the five shared steps that the list does not name: the `git` branch step, the `tester` test step, the `docs-updater` step, the final suite run, and the `git` commit step |

Two guards add `security-reviewer` and `migration-reviewer` to the review step. The conditions are
in `claude-home\commands\orchestrate.md`, section "The guards".

The implementer is `dotnet-developer`, `frontend-developer`, `powershell-developer`, or
`container-developer`, chosen by the files that the plan touches. The implementers do not write or
run tests. `tester` does all test work, and edits test files only.

The test step and the fix pass re-test run only the relevant tests. The final suite run runs the
full suite when "The system-wide impact check" in `shared-steps.md` fires. Then it runs the full
suite of each test project that the diff touches. It also runs the full suite of each test project
that tests a project that the diff touches. In `refactor`, it also runs the full suite when step 3
recorded a full-suite baseline.

Otherwise the final suite run runs the relevant tests again when code changed after the last test
step, or it skips. It runs after the docs step and before the commit step.

Two more `tester` scopes exist. The reproduce scope in `bugfix` runs only the new test, and that
test must fail. The baseline scope in `refactor` runs the covering tests, edits no file, and
records the counts. It records full-suite counts only when the impact check fires on the planned
change.

The browser check step runs in `feature` and `bugfix` only. It runs when all three conditions are
true:

- The diff touches a UI file outside the test folders.
- The repository runs as a standalone app: its `package.json` has a `dev` or `start` script.
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
list of these tasks is in `claude-home\CLAUDE-MAIN.md`, section "Orchestrate multi-step work
yourself". Claude sends a git operation to the `git` agent. See the next section.

The full rules are in `claude-home\commands\orchestrate.md` and in the workflow files in
`claude-home\orchestrate\`.

## Git work

The `git` agent does local git work with fixed name rules that fit any repository. The rules are
in `claude-home\agents\git.md`.
The agent works in the repository that your request names, or in the current folder.
It starts a branch, stages and commits, updates a branch from the default branch, pushes, and
manages worktrees. It never stashes. When you have uncommitted changes on the default branch, it
moves them to a new branch with `git switch -c`. It reads the default branch (for example `master` or `main`) from
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
the target branch, and you create the pull request. The agent never force-pushes. When a force push
is needed, it tells you to run the command yourself with `!`.

## Mistakes log

Claude logs its own mistakes in `%USERPROFILE%\.claude\MISTAKES.md`. Each entry holds what
happened, the root cause, the consequence, and the rule that prevents a repeat. The newest entry
is first. The triggers are in the "Mistakes log" section of `claude-home\CLAUDE-MAIN.md`. The
entry format and the rule for a repeat are in the `mistakes-log` skill.

The file is yours:

- The installer does not ship `MISTAKES.md`, and does not overwrite or delete it.
- Claude creates the file at the first mistake.
- Each team member has their own file.

When the same root cause appears 3 times, Claude asks you whether to make it a rule. A team rule
goes into `claude-home\CLAUDE-TEAM.md`, `claude-home\CLAUDE-MAIN.md`, or an agent file in this repository, through a pull request. The
team reviews it there, and each member gets it on the next automatic update.

## What the installer does

1. It copies `claude-home\` into `%USERPROFILE%\.claude`.
2. It merges `settings.json` with your current file. Your own keys, such as `model`, stay. Your own
   hooks and permission rules stay, and the team entries are added once.
3. It merges the `env` block key by key. It adds only the keys that you do not have, and it keeps
   the values that you set.
4. It writes your own profile path into the statusline path and into the hook paths that use
   `{{CLAUDE_HOME}}`. It writes the clone path into the `update.ps1` hook path.
5. It sets `outputStyle` to `AuDHD` in `settings.json` when the value there is missing or `default`.
   It keeps any other style that you set there. This is the user-level default. A style that you
   choose in `/config` for a project stays in that project's `.claude\settings.local.json` and
   takes precedence.
6. It never changes a hook that already exists in your `settings.json`.
7. It adds the MCP servers in `mcp\servers.json` with `claude mcp add --scope user`. An entry has
   the type `stdio` or `http`. The installer finds your existing servers in the `mcpServers` keys of
   `%USERPROFILE%\.claude.json`. When it cannot read that file, it runs `claude mcp get`. It adds an
   entry that has `alwaysLoad` with `claude mcp add-json --scope user`. It never changes or removes
   another server that exists. A changed entry in `servers.json` therefore does not reach a machine
   that has the server. To get the new entry, run `claude mcp remove <name> --scope user`, then run
   `install.ps1` again. One exception exists: an existing server that has no `alwaysLoad` is replaced
   (removed, then added with `add-json`) when the entry in `servers.json` has `alwaysLoad`, and when
   `type`, `command`, and `args` are the same, `env` is absent or empty, and the server has no other
   key. When the add fails, the installer adds the old entry again. It then warns in an automatic
   run and stops with an error in a manual run. When the definition differs, or the installer cannot
   read `.claude.json`, it skips the server and prints a warning. When `npx` is missing for
   a `stdio` server, the installer prints a Node.js 18 warning and still adds the server.
   Before it adds the servers, a manual run installs CodeGraph with
   `npm i -g @colbymchenry/codegraph@latest`. The `install.ps1` run of the automatic update only
   prints a warning, and then `update.ps1` does the install. The installer skips CodeGraph when it is
   already installed, and it never upgrades it. When npm fails, the installer prints a warning and
   continues. `-SkipMcp` skips this step.
8. It records the path of each file that it installs in
   `%USERPROFILE%\.claude\team-setup\install-state.json`. It overwrites an installed file that
   differs from the team copy. It makes no backup. It deletes a file that an earlier install added
   and the repository no longer ships. This includes the files of a top-level folder that the
   repository removed. It never deletes a file that it did not install. It stops with an error when
   `claude-home\` holds no file, because the clone is then broken. It skips a saved path that is
   empty, is absolute, or contains `..` or `:`, and prints a warning.
9. It makes sure that `%USERPROFILE%\.claude\CLAUDE.md` holds the line `@~/.claude/CLAUDE-TEAM.md`.
   It does this at each install and each automatic update. It handles these cases:
   - No file: it creates the file with only the import line.
   - A file without the line: it adds the line at the top. The BOM and the line endings stay.
   - A UTF-32 file: it changes nothing and warns you. Add the line by hand.
   - A symlink: it writes to the target of the link.

## Contents

| Path | What it is |
|---|---|
| `install.ps1` | The installer. It copies `claude-home\` to `%USERPROFILE%\.claude` and merges `settings.json`. See "First install". |
| `update.ps1` | The automatic update. Claude Code runs it at session start. See "Automatic updates". |
| `claude-home\CLAUDE-TEAM.md` | Team global instructions. The installer copies them to `%USERPROFILE%\.claude\CLAUDE-TEAM.md`. They include a pointer to the AuDHD output style, the import of `STE.md`, the work item effort rule, and the code style rules. Read them before you install them. |
| `claude-home\STE.md` | The writing rules (ASD-STE100). `CLAUDE-TEAM.md` imports this file, so the main session and each agent load it. The `devops`, `git`, and `pr-reviewer` agents have `omitClaudeMd: true`, so they read this file themselves. |
| `claude-home\CLAUDE-MAIN.md` | The agent rules and the mistake-log rules for the main session only. The hook `main-session-rules.ps1` prints this file at session start. A subagent does not get it. It tells the main session to send code questions and searches to `Explore`, and web research to `explore-web`. |
| `claude-home\settings.json` | Permission allow, deny, and ask lists, the hooks, the statusline, the model, the effort level, and the setting that disables the claude.ai connectors. |
| `claude-home\agents\` | 17 agents: architect, planner, dotnet-developer, frontend-developer, powershell-developer, container-developer, tester, code-reviewer, style-reviewer, security-reviewer, migration-reviewer, docs-updater, devops, pr-reviewer, git, Explore, explore-web. `architect` runs on opus. `pr-reviewer` runs on sonnet. `planner` runs on sonnet when the task touches 1 project and fewer than 3 files, and on opus otherwise. `code-reviewer`, `security-reviewer`, and `migration-reviewer` run on sonnet, and `/orchestrate` raises them to opus by the "Reviewer model" rules in `orchestrate.md`. The implementers, `tester`, and `docs-updater` run on sonnet. `devops`, `style-reviewer`, and `git` run on haiku. `Explore` runs on haiku too. It overrides the built-in `Explore` agent, so haiku is the default model of that agent. The caller passes `sonnet` to `Explore` for a flow over more than one project or more than about 5 steps. `explore-web` runs on haiku. It has only the tools `WebSearch` and `WebFetch`, and it answers web research questions. A caller can still pass another `model` value in the `Agent` call, and that value wins. `/orchestrate` raises `tester` to opus for concurrency tests, for published contracts, or when `tester` asks for it. `/orchestrate` sets the model of each agent that it calls. When you call any other agent yourself, name the model in your request. |
| `claude-home\commands\orchestrate.md` | The `/orchestrate` command. See the section above. |
| `claude-home\orchestrate\` | The workflow files of `/orchestrate`: one file for each workflow, and `shared-steps.md` with the steps that several workflows share. `/orchestrate` reads only the files of the chosen workflow. The folder is not under `commands\`, so it adds no slash command. |
| `claude-home\output-styles\audhd.md` | The AuDHD output style. The installer selects it for you when `settings.json` has no other style. You can also select it with `/config` → Output style. |
| `claude-home\skills\strategic-compact\` | The skill and the `UserPromptSubmit` and `PostToolUse` hooks that suggest `/compact` at 15% of the window, then at each further 10%. The hooks read the context size from the file that `statusline.ps1` writes. When that file is missing or older than 10 minutes, they read the transcript. Set `COMPACT_CONTEXT_PERCENT` (default `15`) and `COMPACT_CONTEXT_WINDOW` (default `1000000` tokens, used only when the hooks read the transcript, so set `200000` for a model without the 1M window) to change the values. When the context falls below 15%, for example after `/compact`, the hooks start again. The state is in `~/.claude/cache/strategic-compact/`. Each session has `<session_id>.json` (the last reported level, written by the hook) and `<session_id>.context.json` (the context percent, written by `statusline.ps1`). The hook deletes files older than 7 days. The skill is adapted from `WorldFlowAI/everything-claude-code`. The upstream script counts edits and keys its counter by the shell process id. This version reads the status line file, falls back to the transcript, keys its state by `session_id`, and runs in PowerShell. |
| `claude-home\skills\mistakes-log\` | The skill that holds the entry format, the repeat rule, and the graduation steps for `MISTAKES.md`. |
| `claude-home\hooks\main-session-rules.ps1` | The `SessionStart` hook that prints `CLAUDE-MAIN.md` as context in the main session. It runs at start, resume, clear, and compact. It prints nothing in a subagent. When the file is missing or the read fails, it shows a message that the rules did not load. It also adds the CodeGraph context line when `<repo>\.codegraph\codegraph.db` exists (the repo is the first folder with `.git`, from the working directory up) and `codegraph.cmd` is on `PATH`. |
| `claude-home\hooks\notify.ps1` | The hook that shows a Windows toast when Claude needs you. See the next section. |
| `claude-home\hooks\codegraph-init.ps1` | The synchronous `SessionStart` hook (`startup`, timeout 660 s). Claude Code shows the text "Initializing CodeGraph..." while it runs. It runs `codegraph init --yes` in the git repo of the session when the repo has no CodeGraph index. The first start in such a repo waits for the init. It does nothing in a subagent, when `codegraph` or git is missing, outside a git repo, in your home folder, in a drive root, or in a repo that tracks `.codegraph` (any letter case). It adds `.codegraph/` to `.git/info/exclude` of the repo (the common git folder, so all worktrees), so `git status` stays clean. It stops its own process after 570 s. After a success it prints "CodeGraph indexed <repo> in <N> s." and adds the CodeGraph context line to the session context. After a failure or a timeout it prints "CodeGraph init failed in <repo>. The hook tries again after 24 h. See <log>." and writes `%USERPROFILE%\.claude\team-setup\codegraph-init-<hash>.failed`, and it skips that repo for 24 hours. A success deletes the file. A pending marker `%USERPROFILE%\.claude\team-setup\codegraph-init-<hash>.pending` makes a run that was killed during init run init again. Every other path prints nothing. The `codegraph` MCP server looks for the index again at each tool call, so the index works in the same session. The log is `%USERPROFILE%\.claude\team-setup\codegraph-init.log` (1 MB rotation). The hook has no opt-out. In the mode `worktree`, three async `PostToolUse` hooks (timeout 660 s) index a new worktree. The matchers are `EnterWorktree`, `Bash` with the condition `Bash(*worktree add*)`, and `PowerShell` with the condition `PowerShell(*worktree add*)`. The hook finds new worktrees with `git worktree list --porcelain`. It indexes a worktree only when the main repo has an index, the worktree has no index, and the `.git` file of the worktree is under 10 minutes old. The run has a budget of 600 s. It skips UNC paths, and it deletes `.failed` and `.pending` markers older than 30 days. |
| `claude-home\hooks\codegraph-search-guard.ps1` | The hook that blocks a code search until a `codegraph_explore` call runs or 3 searches are denied. The main session and each agent send code questions and searches to `Explore`, and the hook is the fallback for a search that runs inline. Mode `pre` is a synchronous `PreToolUse` hook (matcher `Grep|Glob|Bash|PowerShell`, timeout 10 s). It denies a search with `grep`, `egrep`, `fgrep`, `rg`, `findstr`, `Select-String`, `sls`, `git grep`, or `xargs grep`, `sed` with a regex address, and the Grep tool, when the filter is absent or names `.cs`, `.ts`, `.tsx`, `.js`, or `.jsx`. It also denies a file-name search with the Glob tool, `find`, or a recursive `Get-ChildItem`, `gci`, `dir`, or `ls` listing, when the name pattern has no extension or names a code extension. A name that is a known extensionless file, such as `Dockerfile`, a name with a dotted prefix such as `MyApp.Services*`, and a directory search are allowed. A Glob tool call is allowed when the file-name part of the pattern starts with a literal name before any wildcard, such as `**/OrderService*.cs`, so the model can get the file names of one class. The deny reason tells the agent not to repeat the blocked search with another tool. It denies only when the resolved search path is inside a folder that has `.codegraph\codegraph.db`, and `codegraph.cmd` is on `PATH`. The hook walks up from each path to the nearest index. It follows `cd`, `Set-Location`, `sl`, `pushd`, `popd`, and Git Bash `/d/...` paths. It skips the agents `git`, `devops`, `pr-reviewer`, `claude-code-guide`, and `statusline-setup`. A search path outside every index is allowed, and a UNC path never reaches the disk. `git ls-files <pathspec>` is a file-name search when the last path part has a wildcard or a dot. Mode `post` is a `PostToolUse` hook (matcher `mcp__codegraph__codegraph_explore`) that opens the gate. The gate of a session and agent opens after one `codegraph_explore` call or after 3 denies. After the gate opens, a search for a symbol name (a camelCase, PascalCase, or `snake_case` identifier) is still denied, until a `codegraph_explore` call follows a deny of the same names, or until 3 symbol denies run with no call between them. A plain-text search runs. In a subagent, a closed gate can still deny the first inline Grep or Glob code search, up to 3 times, because the rule tells a subagent not to call `codegraph_explore` only to open the gate. The state is in `%USERPROFILE%\.claude\team-setup\codegraph-search-guard\` (files older than 7 days are deleted). The log is `%USERPROFILE%\.claude\team-setup\codegraph-search-guard.log` (1 MB rotation). It fails open: an error or a timeout lets the call run. The hook does not model the `(cd x; ...)` subshell scope or backtick substitution, and it does not filter a mapped network drive. It checks only the first 20 search paths of a call. `git -C x grep` is not matched. Each Grep, Glob, Bash, and PowerShell call starts `pwsh` once, about 1 second, also for a command that is not a search. The hook has no opt-out. |
| `claude-home\statusline.ps1` | The statusline script. It shows the context percent as `ctx N%` and the session tokens as `session <N> tok`. It also writes the context size of the session for the strategic-compact hooks. |
| `mcp\servers.json` | User-scope MCP servers: `microsoft-learn` (http), `playwright` (stdio, `cmd /c npx -y @playwright/mcp@latest --headless --isolated --browser msedge --output-dir %TEMP%\playwright-mcp`), `context7` (http, no key), and `codegraph` (stdio, `cmd /c codegraph serve --mcp`, `alwaysLoad`). See "MCP servers". |

## MCP servers

The installer adds four MCP servers at user scope. See step 7 of "What the installer does".

The team settings disable the claude.ai connectors with `"disableClaudeAiConnectors": true`. To
enable the connectors again, set `"disableClaudeAiConnectors": false` in your own `settings.json`.

| Server | Type | Use |
|---|---|---|
| `microsoft-learn` | http | Microsoft and Azure documentation. |
| `playwright` | stdio | The browser check step of `tester`. It runs Microsoft Edge headless and isolated. |
| `context7` | http | Library documentation. It needs no key. |
| `codegraph` | stdio | The code index of the repo. The main session and each agent send code questions and searches to the `Explore` agent, which uses the tool `codegraph_explore`. The section "Send code questions and searches to Explore" (in `CLAUDE-MAIN.md` for the main session, in `CLAUDE-TEAM.md` for subagents) allows an inline call only for a narrow case. The "Code search" rule in `CLAUDE-TEAM.md` tells the reader how to call the tool then. The entry has `alwaysLoad`, so Claude Code does not defer the tool. When a session still defers it, the rule tells the reader to load it with ToolSearch `select:mcp__codegraph__codegraph_explore`. The rule also asks the reader, before each Grep on a code file, whether the target is a symbol name. They use Grep and Glob when the search text is not a symbol name, when the file type is not indexed (such as PowerShell, Markdown, JSON, and config files), when the repo has no index, or when the tool is missing. The agents `architect`, `planner`, `code-reviewer`, `security-reviewer`, `migration-reviewer`, `style-reviewer`, `docs-updater`, `tester`, and `Explore` list the tool. The 4 developer agents have all tools. `git`, `devops`, `pr-reviewer`, and `explore-web` do not get it. `pr-reviewer` and the 8 agents above that list the tool, except `Explore`, have the `Agent` tool. The limit to the `Explore` agent is a prompt rule only. The team settings allow this tool with no prompt (a permanent grant) and set `CODEGRAPH_TELEMETRY` to `0`. |

CodeGraph needs the npm package `@colbymchenry/codegraph` (MIT) and about 265 MB of disk space. To
upgrade it, close all Claude Code sessions, because a running server holds the binary. Then run
`npm i -g @colbymchenry/codegraph@latest`. With nvm4w, a global package belongs to the active
Node.js version.

The hook does not use or delete a committed index. The `codegraph` MCP server still reads a committed
`.codegraph/codegraph.db`.

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
- PowerShell 7.2 or later (`pwsh`) on `PATH`. `install.ps1` and `update.ps1` need it. The hooks and the statusline run through `pwsh`.
- Windows PowerShell 5.1 (`powershell.exe`). Windows includes it. The toast needs it.
- Claude Code CLI (`claude`) on `PATH` for the MCP step.
- Node.js 18 or later (`npx` and `npm` on `PATH`), for the `playwright` MCP server and the `codegraph` package.
- Microsoft Edge, for the `playwright` MCP server.
- Network access to your Azure DevOps server, for the `devops` and `pr-reviewer` agents.
- Authentication for the `devops` agent. In the session, give a personal access token (PAT), the name of an environment variable that holds a PAT, or Windows integrated authentication. A PAT that you paste in the chat stays in the session transcripts under `%USERPROFILE%\.claude\projects`.
