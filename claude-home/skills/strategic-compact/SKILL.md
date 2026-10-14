---
name: strategic-compact
description: Decide when to ask the user to run /compact at a logical task boundary instead of at an arbitrary auto-compact point. Use after a plan is final, after a milestone, after a debug session, and before a context change.
---

# Strategic Compact

Ask the user to run `/compact` at a task boundary. Do not wait for auto-compact. Only the user can
run `/compact`. You cannot run it, and no agent can.

Auto-compact triggers when the context window fills. That point is arbitrary. It often lands
in the middle of a task and it drops context that the next step needs.

## Inside an agent chain

Use the "Compact gates" section of `~/.claude/commands/orchestrate.md`. It is the only full copy
of the gates, the blocks, and the decision rules.

## Outside an agent chain

Ask for a compact at one of these points, when the hook printed a message since the last compact:

1. After the plan is final and before the first edit.
2. After a milestone is done and before the next phase starts.
3. After a debug session ends and the error is fixed.
4. Before the task changes to a different area of the code.

The blocks in `orchestrate.md` apply here too.

## The hook

`suggest-compact.ps1` runs after each `Agent`, `Task`, `Edit`, and `Write` call. It reads the
transcript of the session and takes the context size from the usage of the last reply of the main
session.

1. At 30% of the context window it prints one message.
2. After that, it prints one message at each further 10%.
3. When the context falls below 30%, for example after `/compact`, it starts again. A smaller
   drop does not reset it.

The hook never compacts anything. It states the size. You decide.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `COMPACT_CONTEXT_PERCENT` | `30` | The percent of the window for the first message. |
| `COMPACT_CONTEXT_WINDOW` | `1000000` | The size of the context window in tokens. Set `200000` for a model without the 1M window. |

State files live in `~/.claude/cache/strategic-compact/`. One file per session. The hook
deletes files older than 7 days.

## Source

Adapted from `WorldFlowAI/everything-claude-code`, skill `strategic-compact`.
The upstream script counts edits and keys its counter file by the shell process id, so the count
resets to 1 on every run. This version reads the context size from the transcript, keys its state
by `session_id`, and runs in PowerShell.
