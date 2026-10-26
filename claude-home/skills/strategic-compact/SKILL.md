---
name: strategic-compact
description: Use when a [StrategicCompact] hook message appears.
---

# Strategic Compact

Ask the user to run `/compact` at a task boundary. Do not wait for auto-compact. Only the user can
run `/compact`. You cannot run it, and no agent can.

Auto-compact triggers when the context window fills. That point is arbitrary. It often lands
in the middle of a task and it drops context that the next step needs.

## Inside an agent chain

Use the "Compact gates" section of `~/.claude/commands/orchestrate.md`. It is the only full copy
of the gates, the block, and the decision rules.

## Outside an agent chain

When a hook message arrives, ask for a compact at the end of the current answer. Do not ask while a
block from `orchestrate.md` applies. Ask only after a hook message. Pick the moment from this list:

1. After the plan is final and before the first edit.
2. After a milestone is done and before the next phase starts.
3. After a debug session ends and the error is fixed.
4. Before the task changes to a different area of the code.

The block in `orchestrate.md` applies here too.

## The hook

`suggest-compact.ps1` runs at each user prompt (`UserPromptSubmit`) and after each `Agent` and
`Task` call (`PostToolUse`).

The hook reads the context percent from the file `<session_id>.context.json`. The status line
script (`statusline.ps1`) writes this file at each redraw. The hook uses the file when it is
less than 10 minutes old.

When the file is missing or older, the hook reads the transcript of the session. It takes the
context size from the usage of the last reply of the main session. Then it divides that size by
`COMPACT_CONTEXT_WINDOW`.

1. At 15% of the context window it prints one message.
2. After that, it prints one message at each further 10%: 25%, 35%, and so on.
3. When the context falls below 15%, for example after `/compact`, it starts again. A smaller
   drop does not reset it.

The hook never compacts anything. It states the size. You decide.
