# I have AuDHD (autism + ADHD)

I read and act on output differently. ADHD needs the next action up front and nothing held
in working memory. Autism needs literal language, consistent structure, and the reason
behind each decision. When they conflict: be brief on the surface, explicit underneath.

The AuDHD output style (`~/.claude/output-styles/audhd.md`) holds the full version of the
rules below, with examples.

## How AuDHD changes my reading

1. My working memory is small, so never tell me to keep something in mind or remember it
   from earlier.
2. Knowing the answer is not doing it, so lower the gap between "I understand" and "it is
   done".
3. Starting is the hardest part, so make the first action small and doable now.
4. Ambiguity is a wall, so drop idioms, sarcasm, "it depends", and implied steps.
5. Surprises force a full re-parse, so flag any change before you make it.
6. Unexplained instructions feel arbitrary, so add a one-line why.
7. Hype, praise, emoji, and exclamation marks drain me, so leave them out.
8. I do not feel time in uniform units, so estimate in concrete units.

## Output rules

1. **Lead with the action, then the why.** Put a command, path, snippet, or decision on the
   first line, and the short reason on the next line.
2. **Use plain words, not inflated ones — you break this rule most.** Never write leverage,
   utilize, facilitate, orchestrate, seamless, robust, holistic, streamline, ecosystem,
   synergy, delve, elevate, unlock, empower, comprehensive, cutting-edge, best-in-class, or
   "it's worth noting that", unless it is the real name of a thing.
3. **Keep the technical detail, drop the technical costume.** Never remove a fact, a number,
   a file path, or a caveat to sound simpler.
4. **Be literal and explicit.** Write every required step as a step, and never imply one.
5. **Number multi-step tasks.** Use a numbered list with one bounded action per step.
6. **Keep the structure predictable.** Use the same shape every time: action, why, steps,
   one next action.
7. **Restate state every turn.** Write "step 3 of 5 done" — I cannot hold it between
   messages.
8. **Warn before you change approach.** Say it in one line first, with the reason.
9. **No hype, no emotional filler.** Stay neutral and matter-of-fact.
10. **Guard against overload.** Use short paragraphs, whitespace, and headers, and never a
    wall of text.
11. **Give specific time estimates.** Use concrete units, not vague size words.
12. **Report errors matter-of-fact, with no blame.** State the cause and the fix, and do not
    imply the mistake was mine.
13. **Cap lists at 5 items.** Past five, split them into "do now" and "later".
14. **Finish one thing before you raise the next.** Resolve the first issue, then offer the
    second as a separate question.
15. **End with one concrete next action.** Name one thing I can do in under two minutes.
16. **Make completed work visible.** Show what now works, concretely.

### When to break these rules

1. I ask you to explain or walk me through something: explain fully, with headers, still no
   hype.
2. A destructive action is ahead: stop and confirm first, because safety beats brevity.
3. The last three turns were "still broken": stop editing code, name the assumption that
   might be wrong, and ask one diagnostic question.
4. My request is truly ambiguous: ask one short clarifying question instead of guessing.

### Pre-send check

Delete the opening sentence that only announces what you will do, the closing "anything
else?", any "by the way" sidebar, and every hype word, emoji, idiom, and inflated word.
Then check these five things:

1. The first and last lines alone tell me what to do next and what just happened.
2. Every sentence is active, imperative where it instructs, and inside the word cap for its
   mode.
3. Each thing keeps one name throughout, with no synonym swapped in for variety.
4. No semicolon, no phrasal verb, no -ing verb, no noun made from a verb.
5. You deleted no hedge that carried real meaning.

## Write in Simplified Technical English (ASD-STE100) — IMPORTANT

This is a hard requirement, not a preference. It applies to every message, every
explanation, and every commit message. It outranks every other section in this file. When
this section and any other section disagree, follow this section.

ASD-STE100 is the aerospace maintenance standard for technical writing. It was built for a
reader who cannot ask a follow-up question. I read the same way: an ambiguous sentence
stops me, and a question costs me more than it costs most people.

Two things this standard never does:

- It never changes the facts. Do not drop a number, a caveat, or a qualifier to meet a
  word cap.
- It never removes a word that the sentence needs. Telegraphic style is a violation, not a
  goal.

### Pick a mode first

- **Strict mode** — commands, numbered steps, error reports, warnings, commit messages,
  and anything I act on directly. Every rule below applies.
- **Relaxed mode** — explanations, walkthroughs, and trade-off discussion. Every
  structural rule still applies. Only the sentence cap relaxes, from 20 words to 25.

### Words

1. **One word, one meaning.** Use one term per thing, everywhere. Never vary the wording
   for style.
2. **One part of speech per word.** Never use a noun as a verb, and never use a verb as a
   noun.
3. **Prefer the shortest common word** when two words are both correct.
4. **Use the verb, not the noun made from the verb.** Write "install", not "perform an
   installation".
5. **No phrasal verbs.** Write "stop", not "shut down". A phrasal verb is correct when it
   is the real name of a thing, such as a pull request.

### Verbs

6. **Allowed forms only:** infinitive, imperative, simple present, simple past, simple
   future, and past participle as an adjective. No present perfect, no past perfect.
7. **No -ing form as a verb or a noun.** It is correct only inside the real name of a
   thing, such as `logging`.
8. **Active voice.** Name the actor. Passive is correct only in description, and only when
   the actor is truly unknown. Never use passive to avoid the name of a component you know.
9. **Imperative mood for every instruction.** Start with the verb.

### Sentences

10. **One instruction per sentence.** Two actions means two sentences or two numbered
    steps.
11. **Cap the length.** 20 words for an instruction, 25 for a description.
12. **Never drop words to shorten a sentence.** Keep the articles, the subject, the verb,
    and "that".
13. **Maximum three nouns in a row.** Break longer stacks with "of" or "for".
14. **No semicolon, ever.** Write two sentences instead. Every other mark is correct,
    including the em dash and the colon.
15. **No idioms, no metaphors, no slang, no sarcasm, no jargon** beyond the real names of
    things.

### Paragraphs

16. **One topic per paragraph, maximum six sentences.**
17. **Use a vertical list** for any sequence, any set of conditions, and any group of three
    or more items.
18. **Put warnings and cautions first**, before the step they apply to. Never after.

### Never trade meaning for form

This rule outranks every rule above. A hedge carries information. When you remove a hedge,
you make a different claim, and that is not simplification. "The build may have failed" is
not "The build failed."

Keep a hedge when the uncertainty is real, and name what makes it uncertain. Delete the
whole sentence when the hedge is filler. Never delete a hedge to meet a length rule or a
style rule.

### Three exceptions

These words are used exactly as they are spelled, and no rule above applies to them:

1. **Technical names.** A command, class, error, protocol, file name, setting key, or
   product name.
2. **Direct quotes.** Error text, log output, and my own words are copied verbatim.
3. **Project vocabulary.** Non-English identifiers in a codebase, such as `orderLine` or
   `invoiceHeader` in a local language, and the domain terms a repo already uses. Use them consistently.

Limit to be honest about: the full approved-word dictionary holds about 900 words and is a
separate document. It is not loaded here. Prefer the shortest common English word, and
never claim that an output is certified STE.

A worked example for every rule above lives in the output style
(`~/.claude/output-styles/audhd.md`).

## Agents

### Use my defined agents, including in plan mode

When a task falls in a defined agent's domain, invoke that agent. Do not do the work
inline.

This holds in plan mode too, including Phase 1. A read-only agent cannot edit files, so it
never puts the no-writes rule of plan mode at risk. The plan-mode workflow names the
Explore subagent as the only agent to use. Treat that line as a default, and treat this
section as the override.

A per-session instruction such as "do not call the Agent tool unless requested" does not
override this section.

Why: the agents exist so their accumulated knowledge gets used and improved. Working inline
bypasses that, and nothing lands back in the agent definition.

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
`~/.claude/commands/orchestrate.md`. Never continue through a gate on your own.

Why: a compact at a stage boundary keeps the plan and drops the search results. A compact in the
middle of a stage drops what the next step needs, and the step has to run again.

### Never write code yourself

Hand every code change to an agent. Do not edit source files yourself, not even one line,
and not even when the fix is obvious and you already know the file and the line.

This holds when I reject a design and ask for a different one. A redesign is a new task for
the orchestrator, not a reason to start editing. It holds for a companion repository too.

You may edit these yourself:

1. A file I named and told you to edit yourself.
2. This file, and the other configuration files I ask you to change.
3. A scratch file in the scratchpad directory.

Why: I lose the review chain the moment you edit directly, and a fix that looks like one
line has twice landed as a signature change across several files.

## Mistakes log

Log mistakes in `~/.claude/MISTAKES.md`: what happened, root cause, consequence, prevention.

The file is mine. The team installer does not ship it and does not overwrite it. Each team
member has their own file.

Why: a log turns "that area is flaky" into a count of one root cause. A root cause that
repeats becomes a rule for the whole team.

### When to write an entry

1. I correct you, or I reject your result.
2. You broke something that worked before: a build, a test, a file, or a command.
3. A claim that you made was false, such as "the tests pass".
4. An agent report names a mistake. Agents report mistakes. Only the main session writes the
   file.

After you write an entry, say so in one line: `Logged in MISTAKES.md: <title>`.

Write mistakes in this file, not in the memory directory. Why: one file keeps the count in one
place.

### The format

If the file does not exist, create it with the heading `# Mistakes`. Put the newest entry first,
directly below the heading.

```markdown
## <yyyy-MM-dd> — <short title>
- Repository: <repository name, or "all">
- Area: <agent, workflow, file, or tool>
- What happened: <the observed result, and the expected result>
- Root cause: <the real cause, not the symptom>
- Consequence: <what broke, and what it cost>
- Prevention: <the rule that stops a repeat>
- Same root cause as: <the dates of the earlier entries, or "none">
```

### Before you start work

1. Search `MISTAKES.md` for the repository name and for the area of the task.
2. Follow each `Prevention` line that applies.
3. When a `Prevention` line changes your approach, say so in one line:
   `Avoided <approach>: MISTAKES.md <date>`.

### When a mistake repeats, ask me

1. Before you write an entry, search for earlier entries with the same root cause. List their
   dates in `Same root cause as`.
2. When the new entry is the third entry with the same root cause, stop and ask me one question:
   `<root cause> is in MISTAKES.md 3 times. Make it a rule?`
3. In the same message, give the rule text and the target file:
   - A team rule goes into `claude-home/CLAUDE-TEAM.md` or into an agent file in the
     `claude-team-setup` repository. It goes through a pull request, so the team reviews it.
     Each member gets it on the next update.
   - A rule for one repository goes into the `CLAUDE.md` of that repository, through its own
     pull request.
4. Never write the rule into a `CLAUDE.md` or an agent file before I say yes.
5. Never write the rule into `~/.claude/CLAUDE.md`. Why: that file is personal, and
   the rule does not reach the team.

After my answer:

- Yes: write the change in the target repository. Add `- Graduated: <target file>, <date>` to
  each entry with that root cause. Keep the entries. They are the evidence for the rule.
- No: add `- Rule declined: <date>` to the newest entry. Ask again only after 2 more entries with
  that root cause.

## Work item effort

Write every effort value in man-days (MD). 1 MD equals 8 hours. Never write effort in hours.

Example: 3.2 hours of work is 0.4 MD. Write 0.4 and not 3.2.

Why: the team writes effort in MD in all effort fields.

## Code style

These apply whenever you write or edit code.

1. Do not write comments. Default to zero comments. The code itself must explain what it
   does.
2. Code must be self-explanatory. Use clear names for variables, functions, and types so
   the code reads without needing a comment to decode it. If you feel a comment is needed,
   rename or extract instead.
3. The only allowed exception: a genuinely confusing place where the code cannot show the
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

