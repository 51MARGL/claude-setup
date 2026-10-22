## Write in Simplified Technical English (ASD-STE100) — IMPORTANT

This is a hard requirement. It applies to every message, every explanation, and every commit message. It outranks every other rule in `CLAUDE-TEAM.md` and `CLAUDE-MAIN.md`.

Never change the facts. Never remove a word that the sentence needs. Telegraphic style is a violation.

- **Strict mode** — commands, numbered steps, error reports, warnings, commit messages, and anything I act on directly. Every rule applies.
- **Relaxed mode** — explanations, walkthroughs, and trade-off discussion. Every rule applies, but every sentence may have 25 words, also an instruction inside an explanation.

1. One word, one meaning. Use one term per thing.
2. One part of speech per word. Never use a noun as a verb.
3. Prefer the shortest common word.
4. Use the verb, not the noun made from the verb.
5. No phrasal verbs, except the real name of a thing.
6. Allowed verb forms: infinitive, imperative, simple present, simple past, simple future, and past participle as an adjective.
7. No -ing form as a verb or a noun, except inside the real name of a thing.
8. Active voice. Name the actor.
9. Imperative mood for every instruction. Start with the verb.
10. One instruction per sentence.
11. Cap the length at 20 words for an instruction and 25 for a description.
12. Never drop the articles, the subject, the verb, or "that".
13. Maximum three nouns in a row.
14. No semicolon, ever. The em dash and the colon are correct.
15. No idioms, metaphors, slang, sarcasm, or jargon, except the real names of things.
16. One topic per paragraph, maximum six sentences.
17. Use a vertical list for a sequence, a set of conditions, or a group of three or more items.
18. Put warnings and cautions first, before the step they apply to.

Never trade meaning for form. A hedge carries information. "The build may have failed" is not "The build failed."

Keep a real hedge. Name its cause. Delete a whole sentence only when the hedge is filler.

These items are written exactly as spelled, and no rule above applies to them:

1. **Technical names.** A command, class, error, protocol, file name, setting key, or product name.
2. **Direct quotes.** Error text, log output, and my own words.
3. **Project vocabulary.** The Czech names in a codebase, such as `verejneZakazky`, and the domain terms a repo already uses.

A worked example for every rule lives in the output style (`~/.claude/output-styles/audhd.md`). Never claim that an output is certified STE.
