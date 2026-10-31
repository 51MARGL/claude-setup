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

# Check the size of orchestrate.md (18,500 or less)
(Get-Content -Raw claude-home\commands\orchestrate.md).Length
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
    `STE.md` with no prompt. The allow entry `mcp__codegraph__codegraph_explore` lets the
    `Explore` agent call CodeGraph with no prompt. The main session reads the two `orchestrate` paths again after a
    compact. Claude Code reads with no approval only inside the working directory and the
    additional directories. The deny entries guard the usual command form. They are not a security
    boundary around the program.
  - `env` and other top-level keys (`model`, `effortLevel`, `env.CODEGRAPH_TELEMETRY`, ...): the installer adds a key only when
    the user does not have it. A changed or deleted value never reaches an existing install.
    `env.CLAUDE_CODE_FORK_SUBAGENT` `0` stops the `agent_summary` calls (a full-transcript model call
    every 30 s for each background agent, only for the label in the agents panel). It also disables
    fork subagents. A later delete of the key does not turn the calls back on for an existing install.
  - `hooks`: a hook has the identity `command` + `args`. A hook with new `args` or a new `matcher`
    is added as a second hook. An existing hook is never changed. A hook can have an `if` key, a
    permission rule that limits when the hook runs. The installer copies `if` with the hook.
  - `statusLine`: replaced.
- **`mcp\servers.json`**: an entry has the type `stdio` or `http`. The installer adds it with
  `claude mcp add --scope user`. An entry with `alwaysLoad` is added with
  `claude mcp add-json --scope user`. The JSON argument gets `\"` escapes under Legacy mode, and
  under Windows mode when `claude` is a `.cmd` or `.bat` file. The installer never changes an
  existing server, with one exception. It replaces a server that has no `alwaysLoad` when the entry
  has `alwaysLoad`, `type`, `command`, and `args` are the same, `env` is absent or empty, and the
  server has no other key. It removes the server, then adds it with `add-json`. On an add failure it
  adds the old entry again, and then warns in a saved-switches run and throws in a manual run. It
  skips with a warning when the definition differs or `.claude.json` is not readable. Any other
  changed entry reaches a machine only after the user runs `claude mcp remove <name> --scope user`
  and `install.ps1` again.
  When `claude` is not on `PATH` (a user with only Claude Desktop), `Write-ClaudeConfigMcpServers`
  writes the missing servers into the top-level `mcpServers` of `%USERPROFILE%\.claude.json`. It uses
  `System.Text.Json.Nodes`, so the key order and all other values stay. The shapes are the CLI
  shapes: `http` has `type` and `url`, `stdio` has `type`, `command`, `args`, and an empty `env`, and
  an `alwaysLoad` entry has the `servers.json` keys and no `env`. It never creates `.claude.json`. It
  warns and writes nothing when the file is missing, empty, or invalid, or when `mcpServers` is not an
  object. It never changes an existing server, with the same `alwaysLoad` exception as the CLI path:
  it sets `"alwaysLoad": true` in place. A different definition gives a warning that tells the user
  to delete the entry from `.claude.json`. The write copies the file to
  `%USERPROFILE%\.claude.json.bak`, writes `.claude.json.team-setup.tmp`, and reads the file again. When the text
  changed, it merges once more, and it skips with a warning when the file changes a second time. Then
  it runs `Move-Item -Force`. The output has LF line ends, no BOM, and the final newline of the old
  file. An IO error warns in a saved-switches run and throws in a manual run. `-WhatIf` writes
  nothing. Known and accepted: the move replaces a symbolic link at `.claude.json` with a regular
  file, a ReadOnly attribute does not stop the write, and a running Claude Code process can write
  its old copy back. The next run adds the servers again.
  `Get-Command` for `npm.cmd`, `claude`, and `git` takes the first match when `PATH` has two.
  Before it adds the servers, `Install-CodeGraph` in `install.ps1` runs
  `npm.cmd i -g @colbymchenry/codegraph@latest` in a manual run only. A saved-switches run of
  `install.ps1` (the auto-update) runs no npm and prints a warning, and then `update.ps1` installs
  CodeGraph. `-SkipMcp` skips it. It never upgrades. An npm
  failure gives a warning and the install continues. `Install-CodeGraph` in `update.ps1` does the
  install for the auto-update. It runs when `install-state.json` exists, `switches.SkipMcp` is not
  true, and `codegraph` is not on `PATH`. It tries once per 24 hours and records the time in
  `%USERPROFILE%\.claude\team-setup\codegraph-install-last-try.txt`. It deletes the file when
  `codegraph` is installed. The lock file `codegraph-install.lock` in the same folder makes a second
  session skip. When `npm.cmd` is missing, the message shows the npm command. When `npm prefix -g`
  already holds `codegraph.cmd` (not on `PATH`) and `package.json` of the package has a readable
  version, it runs no npm and shows no message. When `package.json` has no readable version, the
  install is incomplete and it installs again (once per 24 hours). Otherwise it
  runs the npm command with a timeout of 180 s (`-CodeGraphInstallTimeoutSeconds`). It skips npm when
  less than 210 s of the hook timeout is left. After a success, the message is "The update installed
  CodeGraph <version>. Restart Claude Code ..." (the version only when it matches a semver pattern).
  On a failure the message is "CodeGraph failed to install. Run: npm i -g ... Then restart Claude Code.
  See <log>." The `update.log` file holds the npm output.
  This is an unattended `npm i -g` from the public registry, with the package install scripts. Both
  npm child processes (`npm prefix -g` and the install) run in `%USERPROFILE%\.claude\team-setup`
  and get no `ANTHROPIC_*` or `CLAUDE_CODE_*` variable. This is defence in depth only. The install
  scripts run as the user and can read user files, such as `%USERPROFILE%\.claude\.credentials.json`.
- **`hooks\codegraph-init.ps1`**: a synchronous `SessionStart` hook (`startup`, timeout 660, `async` false,
  `statusMessage` "Initializing CodeGraph..."). It runs `codegraph init --yes <toplevel>` in each git
  repo that has no index. The first start in such a repo waits for the init. It does nothing in a repo
  that tracks `.codegraph` (any letter case), and also when `git ls-files` fails. The script kills
  its own process tree after 570 s, below the hook timeout. After a success it prints "CodeGraph
  indexed <repo> in <N> s." and returns `additionalContext` with the CodeGraph context line. After a failure or a timeout it prints "CodeGraph init failed in <repo>.
  The hook tries again after 24 h. See <log>." and writes
  `%USERPROFILE%\.claude\team-setup\codegraph-init-<hash>.failed`. It skips that repo for 24 h. A
  success deletes the file. A pending marker
  `%USERPROFILE%\.claude\team-setup\codegraph-init-<hash>.pending` makes a run that was killed during
  init run init again. Every other path prints nothing. The `codegraph` MCP server looks for the
  index again at each tool call, so the index works in the same session. It adds `.codegraph/` to `.git/info/exclude` (the common dir, so all worktrees) to keep `git status`
  clean and to stop `git add -A` from adding `.codegraph/.gitignore`. It has no opt-out.
  - `worktree` mode (`codegraph-init.ps1 worktree`): three async `PostToolUse` hooks, timeout 660. The
    matchers are `EnterWorktree`, `Bash` with `if` `Bash(*worktree add*)`, and `PowerShell` with `if`
    `PowerShell(*worktree add*)`. The hook finds new worktrees with `git worktree list --porcelain`.
    It indexes a worktree only when the main repo has an index, the worktree has no db, and the
    `.git` file of the worktree is under 10 minutes old. The run has a budget of 600 s. For a shell
    call, it reads `git -C` only in the `worktree add` segment. It skips UNC paths. It deletes
    `.failed` and `.pending` markers older than 30 days. The `SessionStart` behaviour is the same.
- **`hooks\codegraph-search-guard.ps1`**: one script with the mode `pre` or `post`.
  - `pre`: a synchronous `PreToolUse` hook (matcher `Grep|Glob|Bash|PowerShell`, timeout 10). It denies a
    code search when all of these are true: the call is a search (the Grep tool, or a shell segment
    that starts with `grep`, `egrep`, `fgrep`, `rg`, `findstr`, `Select-String`, `sls`, `git grep`,
    `xargs grep`, `sed` with a regex address, or `Select-String` after `Get-ChildItem`, `gci`, `dir`, or `ls`) and the filter is
    absent or names `.cs`, `.ts`, `.tsx`, `.js`, or `.jsx`; or the call is a file-name search (the
    Glob tool, `find`, or a listing with `Get-ChildItem`, `gci`, `dir`, or `ls`) and the name
    pattern has no extension, or names a code extension; the resolved search path is inside an index
    (the hook walks up from each path to the nearest `.codegraph\codegraph.db` whose index holds at
    least 1 file, and stops at a folder with `.git` and no db; a path outside every index is allowed;
    a UNC path never reaches the disk; see "Index check" below);
    `codegraph.cmd` is on `PATH`; `agent_type`
    is not `git`, `devops`, `pr-reviewer`, `claude-code-guide`, or `statusline-setup`; and the gate of
    this session and agent is closed, or the search is a blocked symbol search (see below).
  - Path and command rules:
    - A search of a folder that is an ancestor of the index folder is gated. The hook follows `cd`,
      `Set-Location`, `sl`, `pushd`, `popd`, and Git Bash `/d/...` paths.
    - The hook uses the folder of `git -C <path>` for `git grep` and `git ls-files`. Several `-C`
      combine as in git. Before the subcommand, it skips `-c <k=v>`, and `--git-dir`, `--work-tree`,
      `--namespace`, `--config-env`, `--super-prefix` with their value, and `-p`, `-P`, and each
      other `--` option as one word. Any other option with one dash stops the match.
    - A negated glob (`!...`) is not a filter.
    - An assignment, a shell keyword, `$(`, `(`, or `{ }` does not hide the search command. The hook
      skips `xargs` flags, and `xargs grep` counts also with no pipe. A search inside a
      `ForEach-Object` block uses the filter of the listing before the pipe. PowerShell common value
      flags such as `-ErrorAction` are not path operands.
    - The hook checks a comma list and `{a,b}` braces part by part, up to 32 parts. More than 32
      parts is a code search.
    - `git ls-files <pathspec>` is a file-name search when the last path part has a wildcard or a
      dot. A bare folder is allowed. A `:` pathspec is not a name pattern.
  - Index check: a folder with `.codegraph\codegraph.db` counts as an index only when
    `codegraph status --json <root>` reports `fileCount` above 0. An index with 0 files counts as no
    index, and the walk continues up. A repo whose files CodeGraph does not index (such as this
    repo: `.ps1`, `.md`, `.json`) gets no gate. The hook runs the status call at each check that
    reaches an index. It keeps no cache on disk, and one hook run checks each root once. The call
    has a timeout of 6 s, and runs in `%USERPROFILE%\.claude\team-setup`. A status failure, a
    timeout, or bad JSON counts as no index, so the search runs. The hook skips the call, and the
    search runs, when the root path has one of `& | < > ^ % ! ( ) , ; =`, whitespace, or `"`,
    because `codegraph.cmd` runs through `cmd.exe`, which parses these characters in an unquoted
    argument. One stopwatch covers the hook run, with a budget of 8500 ms. The hook starts a status
    call only when the call can finish inside the budget, so only the first index in one run gets
    checked. A later index counts as no index.
  - `sed` rule: a `sed` segment is a search only when its script has a regex address, such as
    `/pattern/p` or `/a/,/b/p`. The pattern is the regex in the first address. `sed` with only
    line-number addresses (`sed -n '10,40p' file`), with `-i` or `--in-place`, or with `-f` is
    not a search. The filter and repo checks are the same as for `grep`.
  - Symbol rule: for a content search, the hook takes the pattern (the Grep tool `pattern`, the value
    of `-e`, `--regexp`, or `-Pattern`, or else the first word that is not a flag or a flag value, or
    the `sed` address regex). It strips `\b`, `\<`, `\>`, `^`, `$`, a trailing `(` or `\(`, and a
    leading `\.` from each alternative (split on `|` and `\|`). The pattern is a symbol pattern when
    each alternative is an identifier of at least 4 characters that is camelCase or PascalCase, or
    has `_` between letters and at least one lowercase letter. A plain word such as `error`, and an
    UPPER_SNAKE name such as `CHECK_CLIENT`, is not a symbol pattern. When the gate is
    open, the hook denies a symbol search, with two exceptions:
    - (a) Each symbol name was in an earlier symbol deny of this gate key, and a `codegraph_explore`
      call ran after that deny. A symbol that CodeGraph cannot find can be searched after one try.
    - (b) 1 symbol deny ran with no `codegraph_explore` call after it. The next symbol search runs.
    A symbol search with a closed gate follows the normal closed-gate rule (the 1-deny rule). The deny
    also records the names, so exception (a) applies after the next `codegraph_explore` call.
  - Allowed searches (the hook exits with no deny, also with a closed gate):
    - A file list: a Grep `glob` or a Glob `pattern` where each name (after brace expansion and a
      split on `,`, up to 32 parts) has no `*`, `?`, `[`, `{`, or `}` in the file-name part, has a
      letter, and has an extension, such as `SasCryptoUtils.cs` or `{A,B}.cs`. A name that starts
      with `!` is not a file list. A `**/` folder prefix is allowed. A Grep with `path` of one existing file is allowed, and the file extension is not
      used as a filter. A shell `grep` or `rg` is allowed when every path operand is an existing
      file (1 to 20 operands, none with `*`, `?`, `[`, `{`, `$`, `%`, or a backtick).
    - A folder with no code file: a search path that is a directory below an indexed root (not the
      root, not a folder above it) and holds no `.cs`, `.ts`, `.tsx`, `.js`, or `.jsx` file does not
      reach the index. The check walks up to the index and stops at a `.git` folder or file. It
      scans the folder before the status call, so it starts no node process. At 5,000 files or
      300 ms it counts the folder as code. An error counts as code.
    - A config key: a content pattern where each alternative matches
      `^[A-Z][A-Z0-9]*(_[A-Z0-9]+)+$` (the strip rules of the symbol rule apply), such as
      `CHECK_CLIENT_CERTIFICATE`. CodeGraph does not index JSON, YAML, or environment keys. The
      check runs after the index check. `CHECK_CLIENT|FooBar` is not a config key, and it is not a
      symbol pattern.
  - `post`: a `PostToolUse` hook (matcher `mcp__codegraph__codegraph_explore`, timeout 10) in the
    same array as the `Agent|Task` strategic-compact hook. It writes the `.open` marker, also when
    CodeGraph returns an error text. It also moves the names from `.symbols-denied` to
    `.symbols-explored`, and deletes `.symbols-denied` and `.symbol-denies`.
  - The gate key is `<session_id>-<agent_id|main>`. The gate opens after one `codegraph_explore` call
    or after 1 deny. After the gate opens, only a plain-text search runs freely. The state is in
    `%USERPROFILE%\.claude\team-setup\codegraph-search-guard\` (`.open`, `.denies`, `.symbol-denies`,
    `.symbols-denied`, `.symbols-explored`). The deny path deletes files older than 7 days, also
    these new files. The log is
    `%USERPROFILE%\.claude\team-setup\codegraph-search-guard.log` (1 MB rotation). It has one line
    for each deny, with only the tool name, the agent type, and the search command word. A symbol
    deny adds the word `symbol`. The log has no pattern and no symbol name.
    The deny reason also tells the agent not to repeat the search with another tool. It depends on
    the agent type. For the type `Explore`, it tells the agent to call `codegraph_explore` (the 3
    shared sentences of item 16), and a symbol deny names the blocked symbols and says that a search
    for the same names runs after one CodeGraph call. For every other type, also an empty type (the
    main session), it tells the agent to send the search to `Explore` with the `Agent` tool and not
    to call `codegraph_explore` and then repeat the search. A symbol deny gives the blocked symbol
    names to `Explore`. Why: a call to `codegraph_explore` by an agent that is not `Explore` filled
    its context with source, and then the agent ran the same search.
  - Accepted cost: the rule in "Send code questions and searches to Explore" tells a subagent not to
    call `codegraph_explore` only to open the gate. In a subagent, a closed gate can still deny the
    first inline code search once (Grep, Glob, or a shell search).
  - File-name search rules: `find` counts its `-name`, `-iname`, `-path`, `-ipath`, `-wholename`, and
    `-iwholename` values. It counts `-path` only with a wildcard, and `-regex` only with a code
    extension. A listing counts its `-Filter`, `-Include`, and wildcard values, and only with
    recursion (`-Recurse`, `-R`, or `**`). `find -type d` and `-Directory` are skipped, and so is
    `-Exclude`. A name with no extension is a search, except a name on the allow list (`Dockerfile`,
    `Makefile`, `README`, `LICENSE`, ...). A Glob tool call is allowed when the file-name part of
    the pattern starts with a literal name (`[A-Za-z0-9_-]` with a letter) before any wildcard, such
    as `**/OrderService*.cs`. This lets the model get the file names of one class (item 5 of "Code
    search" in `CLAUDE-TEAM.md`). A Glob that starts with a wildcard, such as `**/*.cs`, is a search.
  - It fails open: an error, a timeout, or a malformed or empty input lets the call run. It only
    denies or prints nothing, and never returns "allow".
  - Limits: the `(cd x; ...)` subshell scope and backtick substitution are not modelled. An operand
    with `$`, `%`, or a backtick uses the directory instead. A mapped network drive is not filtered.
    The hook checks only the first 20 search paths of a call. It does not check a path after the 20th.
    `--git-dir` and `--work-tree` do not change the search folder. `--attr-source <tree-ish>` is
    skipped without its value, so the value hides the subcommand and the search is not matched. A dotted name such as `MyApp.Services*` is allowed. A listing with no recursion is
    allowed. `Where-Object -like` after a listing is not matched. `find -regex` with a group, such
    as `.*\.(cs|ts)`, is allowed. `awk` and `perl` are not matched. The symbol test is a heuristic
    for the shape of a name, so a symbol in a pattern with regex syntax is not found, and a
    camelCase word that is not a symbol is blocked. The no-code folder check counts a folder as code
    after 5,000 files or 300 ms. The file-list and shell-operand exceptions need a file that exists
    now. A name that does not exist yet is searched as usual. The deny count is not atomic. Each Grep, Glob, Bash, and PowerShell
    call starts `pwsh` once (about 1 s), also for a command that is not a search. A search that
    reaches an index costs about 2 s more, because the status call starts node. A repo path with a
    space or one of the characters in "Index check" gets no guard. The hook has no opt-out.
- **Placeholders**: the installer replaces `{{CLAUDE_HOME}}` and `{{TEAM_SETUP_REPO}}` with real
  paths. Use them in every path in `settings.json`. The exception: a permission rule path uses `~/`
  (home-relative) and not a placeholder.
- **`CLAUDE-TEAM.md`**: copied. The user's own `%USERPROFILE%\.claude\CLAUDE.md` gets only the
  import line `@~/.claude/CLAUDE-TEAM.md`. `CLAUDE-TEAM.md` imports `STE.md` with the line
  `@~/.claude/STE.md`. It also holds the section "Send code questions and searches to Explore" for
  subagents.
- **`STE.md`**: copied. It holds the full STE rules. The main session and each agent load it through
  the import in `CLAUDE-TEAM.md`. The `devops`, `git`, and `pr-reviewer` agents have
  `omitClaudeMd: true`, so they read `STE.md` themselves.
- **`CLAUDE-MAIN.md`**: copied. It holds the rules for the main session only. The hook
  `hooks\main-session-rules.ps1` (a `SessionStart` hook) prints it as context. A subagent gets no
  copy, because the hook exits when `agent_id` is set. The hook runs at `startup|resume|clear|compact`.
  When the file is missing or the read fails, the hook shows a message that the rules did not load.
  The hook walks up from `cwd` to the first folder with `.git`. It adds the CodeGraph context line
  when `<root>\.codegraph\codegraph.db` exists and `codegraph.cmd` is on `PATH`.
- **`orchestrate\`**: copied. It holds one file for each `/orchestrate` workflow and
  `shared-steps.md`. Step 0 of `commands\orchestrate.md` reads only the files of the chosen
  workflow. The folder also holds 5 rules files that the main session reads on demand:
  `resolve-reference.md`, `findings-rules.md`, `after-compact.md`, `final-report.md`, and
  `effort.md`. The text of these sections lives there, because `orchestrate.md` must stay under the
  cut of 20,000 characters (see "Writing rules"). The folder also holds 3 `agent-*.md` files that
  `reviewer` (security and migration focus) and `tester` (browser check) read on demand. The folder
  is not under `commands\`, because each file there is a slash command.

`update.ps1` names a file in its message when a new commit changes it (`$sensitivePaths`). The list
has 48 paths in 3 groups:

1. The files that run code: `install.ps1`, `update.ps1`, `claude-home/hooks/main-session-rules.ps1`,
   `claude-home/hooks/notify.ps1`, `claude-home/hooks/codegraph-init.ps1`, `claude-home/hooks/codegraph-search-guard.ps1`,
   `claude-home/statusline.ps1`,
   and `claude-home/skills/strategic-compact/suggest-compact.ps1`.
2. The files that set permissions, hooks, tools, or the model: `claude-home/settings.json`,
   `mcp/servers.json`, and the 15 agent files `claude-home/agents/<name>.md`.
3. The rules that the main session loads or follows: `claude-home/CLAUDE-TEAM.md`,
   `claude-home/CLAUDE-MAIN.md`, `claude-home/STE.md`, `claude-home/commands/orchestrate.md`, the 16
   files `claude-home/orchestrate/<name>.md`, `claude-home/output-styles/audhd.md`,
   `claude-home/skills/mistakes-log/SKILL.md`, and `claude-home/skills/strategic-compact/SKILL.md`.

When you add a `.ps1` file, an agent file, or a rules file to `claude-home\`, add its path to
`$sensitivePaths`.

## Texts that must agree

Several files hold the same fact. When you change one, change the others in the same commit.

1. **Agent models and effort**: the `model:` and `effort:` lines of each agent file, the Model and
   Effort columns of the "Model policy" table in `claude-home\commands\orchestrate.md`, the table in
   `claude-home\agents\pr-reviewer.md`, and the `claude-home\agents\` row of the "Contents" table in
   `README.md`.
2. **The guards and the reviewer model**: a guard adds a `Focus:` line to the `reviewer` handoff.
   `orchestrate.md` ("The guards" and "Reviewer model") and `pr-reviewer.md` hold the same text.
   Keep the two texts identical.
3. **The list of tasks that need no agent chain**: only in `claude-home\CLAUDE-MAIN.md`
   ("Orchestrate multi-step work yourself"). `orchestrate.md` points to it. Do not copy it.
4. **Rules from `MISTAKES.md`**: the PowerShell alias ban, the line-endings rule, the task-scope
   rule, and the delete rule (`git rm` for a tracked file, `Remove-Item` only for an untracked file,
   alone in its own call, as the last step) are in several agent files (`dotnet-developer`, `frontend-developer`,
   `powershell-developer`, `container-developer`, `markdown-developer`, `tester`, `docs-updater`).
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
   `dotnet-developer.md`, `frontend-developer.md`, and `reviewer.md`.
9. **The test-run scopes**: `claude-home\orchestrate\shared-steps.md` (the test step, the fix pass,
   and the final suite run), `bugfix.md` (the `reproduce` scope) and `refactor.md` (the `baseline`
   scope) in the same folder, `tester.md`, and `README.md`. The system-wide impact criteria are
   only in `shared-steps.md` ("The system-wide impact check"). `tester.md` and `README.md` point
   to it. Do not copy them. The rule that skips the test step, the browser check step, and the
   final suite run for a Markdown-only diff is in `shared-steps.md` and `README.md`. The
   `plan-test.md` rule is in `shared-steps.md` (test step items 3 and 6) and `tester.md` (start step 5
   and the "Tests" report item). The test step sends a planned test with no report entry back to
   `tester` once. Keep the entry forms (`file:line`, "covered by", "skipped:") the same.
10. **The toast text** "Waiting for agents. Nothing needed from you now.": `orchestrate.md`,
    `README.md`, and `notify.ps1` (`$waitLine`).
11. **The `CLAUDE.md` read step**: the text "The root `CLAUDE.md` of the working directory is already
    in your context" is in `architect`, `planner`, `dotnet-developer`, `frontend-developer`,
    `powershell-developer`, `container-developer`, `markdown-developer`, `tester`, and `reviewer`.
    Keep the 9 texts the same.
12. **The sensitive paths**: `$sensitivePaths` in `update.ps1`, the list in "How the installer treats
    each file" in this file, and the "Security" section of `README.md`. Keep the three lists the
    same.
13. **The update hook timeout**: `$hookTimeoutSeconds` (400) in `update.ps1` and the `timeout` of the
    update hook in `claude-home\settings.json`. The time guard of `Install-CodeGraph` uses the value.
14. **The code-search rule**: "Code search" in `claude-home\CLAUDE-TEAM.md` and "How to search" in
    `claude-home\agents\explore.md`. Keep the same terms, the same list of file types, the ToolSearch
    step, the symbol check before a Grep, the Read exception, and the rule to treat the source that
    `codegraph_explore` returned as read (item 8 in both files, word for word).
15. **The agents with the CodeGraph tool**: the `tools:` line of `architect`, `planner`,
    `reviewer`, `docs-updater`, `tester`, `explore`, and the 4 developer agents (`dotnet-developer`,
    `frontend-developer`, `powershell-developer`, `container-developer`) has
    `mcp__codegraph__codegraph_explore`. `git`, `devops`, `pr-reviewer`, `markdown-developer`, and
    `explore-web` do not get it. The `tools:` line of `pr-reviewer`, `markdown-developer`, and the 9
    agents with the CodeGraph tool, except `explore`, has `Agent`. Every agent file has a `tools:`
    line. An agent with no `tools:` line gets all tools, a skill list, and a deferred-tool list.
    Its start context is much larger. The limit to the `Explore` agent is a prompt rule only.
    Claude Code ignores `Agent(Explore)` in the `tools:` line of a subagent. Keep this
    list the same in `README.md` ("MCP servers").
16. **The CodeGraph context line** ("This repo has a CodeGraph index. Call the `codegraph_explore`
    tool first ..."): `main-session-rules.ps1` and `codegraph-init.ps1`. Keep the two texts
    identical. The line has 5 sentences: 3 shared sentences and 2 sentences that send code questions
    to `Explore`. The deny reason in `codegraph-search-guard.ps1` has only the 3 shared sentences,
    and only for the agent type `Explore`. Every other agent type, also the main session, gets a
    deny reason that sends the search to `Explore`.
17. **The `Explore` routing rule**: the section "Send code questions and searches to Explore" in
    `claude-home\CLAUDE-MAIN.md` (main session) and in `claude-home\CLAUDE-TEAM.md` (subagents).
    Keep the same source list (it has no deny reason, because the guard sends every agent type
    except `Explore` to `Explore`), the override sentence, the path sentence, the Grep and Glob
    conditions, and the `sonnet` or `haiku` rule. The `Model policy` row of `orchestrate.md` has the
    `sonnet` rule too. The `codegraph_explore` conditions differ on purpose: the subagent text is
    wider (1 to 3 named symbols, 1 or 2 calls). The inline search conditions (the folder below the
    repo root, 1 to 3 tool calls, the shell search forms, the rule to send an empty result to
    `Explore`) are the same in both files. The wait rule after an `Explore` start is only in
    `CLAUDE-TEAM.md`. The main session waits by the rule in `orchestrate.md` ("When you end a turn
    only to wait for a background agent"). It does no search of its own that `Explore` can duplicate.
18. **The output switches**: `dotnet-developer`, `frontend-developer`, `powershell-developer`, and
    `tester` use the same switches for the same tool (`-v:minimal -nologo -clp:NoSummary`,
    `--silent`, `tsc --pretty false`).
19. **The self-check and the reviewer checklist**: "Self-check before you report" is identical in
    the 4 developer files. Its items match "Never report" and the conventions checks in
    `reviewer.md`. `markdown-developer` has its own self-check list for Markdown.
20. **The plan sections**: the top-level headings in the "Plan format" of `planner.md` and the split
    rule in "The plan-confirm stop" of `orchestrate.md`. The chunk headings under `## For the
    implementer` and the file names `plan-implement.md` and `plan-implement-<n>.md` are the same in
    both files.
21. **The compact gates and `findings.md`**: the gate letters A to D and `findings.md` are in
    "Compact gates" of `orchestrate.md`, in `claude-home\orchestrate\after-compact.md`, and in
    `claude-home\orchestrate\findings-rules.md` ("Before you ask about findings"). `shared-steps.md` (the
    fix pass, "After each fix pass"), `test.md` (only gate C and gate D apply), and the
    "What /orchestrate does" text of `README.md` use them. Keep the gate letters, the single block,
    and the rule that a fix pass has no limit the same.
22. **The implementer list**: `dotnet-developer`, `frontend-developer`, `powershell-developer`,
    `container-developer`, and `markdown-developer` are in `feature.md`, `planner.md`, `README.md`,
    and the "implementer agents" row of the "Model policy" table in `orchestrate.md`. Keep the five
    names the same.
23. **The `New to the repo:` mark**: the definition is only in "Mark what is new to the repository"
    in `claude-home\CLAUDE-TEAM.md`. The **New to the repo** report item is identical in the 5
    implementer files and `tester.md`. `planner.md` (the plan `## Summary`, the `plan-implement`
    files, and the return), `orchestrate.md` (plan-confirm step 4 and the `state.md` item list), and
    `final-report.md` use the same mark. Do not copy the definition.

## Writing rules for this repository

- Write agent files, commands, `README.md`, and commit messages in ASD-STE100 style, as
  `claude-home\STE.md` defines it. `STE.md` holds the full rules, because agents load it through the
  import in `CLAUDE-TEAM.md` and do not get the output style. `claude-home\output-styles\audhd.md` holds a worked example
  for each rule ("CT rule N").
- Keep CRLF line endings. The repository has no `.editorconfig`. On Windows, `sed -i` in Git Bash
  changes CRLF to LF, so use the Edit tool.
- An agent file starts with frontmatter: `name`, `description` (with the trigger words), `tools`,
  `model`, `effort`, and `experimental.cacheTtl`. The team default is `5m`. Why `cacheTtl`: a gap of
  more than 5 minutes occurs in about 1.5% of subagent turns. A 1-hour cache write costs 2x, against
  1.25x for 5 minutes. The 5 implementers (`dotnet-developer`, `frontend-developer`,
  `powershell-developer`, `container-developer`, `markdown-developer`), `tester`, and `reviewer` use
  `1h`. Why: a long command in these agents (an EF migration of 7 minutes, a SQL generation of
  5 minutes) makes a 5-minute cache expire, and the re-write of a large context costs more than the
  2x price of a 1-hour write. The field needs Claude Code v2.1.248 or later. It overrides `ENABLE_PROMPT_CACHING_1H`.
  The setting `subagentPromptCacheTtl` and the variable `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL`
  override it. The team sets no settings key for it.
- An agent file with the name of a built-in agent (`Explore`) overrides that built-in agent in every
  session.
- The `git` agent never adds a `Co-Authored-By:` line or any other AI attribution line to a commit
  message.
- `MISTAKES.md` belongs to each user and is not in this repository. A rule from it goes into
  `CLAUDE-TEAM.md`, `CLAUDE-MAIN.md`, or an agent file here, through a pull request.
- Keep `claude-home\commands\orchestrate.md` at 18,500 characters or less. Why: after a compact,
  Claude Code injects the skill again and cuts it at 20,000 characters. Move a rarely used section
  to a file in `claude-home\orchestrate\` and add its path to `$sensitivePaths`.
