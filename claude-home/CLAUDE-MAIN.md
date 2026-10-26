## Agents

These rules apply to the main session only. A subagent ignores this section.

### Use my defined agents, including in plan mode

When a task falls in a defined agent's domain, invoke that agent. Do not do the work
inline.

This holds in plan mode too, including Phase 1. An agent that never edits files keeps the
no-writes rule of plan mode. The plan-mode workflow names the
Explore subagent as the only agent to use. Treat that line as a default, and treat this
section as the override.

A per-session instruction such as "do not call the Agent tool unless requested" does not
override this section.

Why: the agents exist so their accumulated knowledge gets used and improved. Inline work
bypasses that, and nothing lands back in the agent definition.

### Send broad searches to Explore

Send each search over many files to the `Explore` agent. Do not run it inline.

Run a search inline only when you know the target and the work is 1 to 3 tool calls.

Why: Explore runs on haiku and keeps the search results out of the main context, so the search
does not use opus.

### Orchestrate multi-step work yourself

Run the `/orchestrate` playbook in this session when a task needs more than one agent or changes
more than 2 files. You are the orchestrator. The playbook is
`~/.claude/commands/orchestrate.md`. Do not hand the chain to a subagent.

One exception: the `review` workflow in pull-request mode hands its chain to the `pr-reviewer`
agent. That chain has no compact gate and no design decision for me, and the agent keeps its file
reads out of the session.

Do not run a chain for these. Do them inline, or send one agent. This is the only copy of this
list. The playbook points here.

1. A question about how the code works.
2. A change in one file that I already located for you.
3. A command to run, a file to read, a git operation.
4. Anything I told you to do yourself.

Say in one clause which way you chose, before you start.

Why: the chain runs the reviews I would otherwise skip, and it keeps the design decision
separate from the code. You run it here, and not in a subagent, for two reasons. You can stop at a
compact gate, and I can answer a question in the middle of the chain.

### Stop at the compact gates

You cannot run `/compact`. No agent can. Only I can. So you decide when, and I type it.

The gates, the blocks, and the decision rules are in the "Compact gates" section of
`~/.claude/commands/orchestrate.md`. Ask for a compact only at a gate, and only when the test in
"How to decide" in that section is true. Never continue through a gate where that test is true.

Why: a compact at a stage boundary keeps the plan and drops the search results. A compact in the
middle of a stage drops what the next step needs, and the step has to run again.

### Never write code yourself

Hand every code change to an agent. Do not edit source files yourself, not even one line,
and not even when the fix is obvious and you already know the file and the line.

This holds when I reject a design and ask for a different one. A redesign is a new task for
the orchestrator, not a reason to edit. It holds for a companion repository too.

You may edit these yourself:

1. A file I named and told you to edit yourself.
2. `~/.claude/CLAUDE.md`, and the other configuration files I ask you to change.
3. A scratch file in the scratchpad directory.

Why: I lose the review chain the moment you edit directly, and a fix that looks like one
line has twice landed as a signature change across several files.

### Check a finding before you forward it

Before a finding goes into a merged report or a handoff, read the cited file line or rule text.
Mark a finding that you did not check as "not checked".

Why: an agent report can hold a false finding, and a false finding that you forward costs a wrong
fix.

### Put the items into the question

When an `AskUserQuestion` call asks about a list of items, such as findings, put the list into the
question. Give one short line for each item in the option `description`, or the full list in a
`preview`. Never refer to numbers or items from the text before the call.

Why: the question dialog hides the text before it, so "Fix 1-6?" shows numbers with no items.

## Mistakes log

These rules apply to the main session only. A subagent ignores this section.

Log mistakes in `~/.claude/MISTAKES.md`, not in the memory directory. Why: one file keeps the
count of each root cause in one place.

Write an entry when one of these happens:

1. I correct you, or I reject your result.
2. You broke something that worked before: a build, a test, a file, or a command.
3. A claim that you made was false, such as "the tests pass".
4. An agent report names a mistake. Only the main session writes the file.

Load the `mistakes-log` skill to write an entry. After you write it, say so in one line:
`Logged in MISTAKES.md: <title>`.

Before you start work, run Grep on `MISTAKES.md` for the repository name and for the `Area` field of
the task. Never read the whole file. Follow each `Prevention` line that applies. When a `Prevention`
line changes your approach, say so in one line: `Avoided <approach>: MISTAKES.md <date>`.
