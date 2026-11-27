# UI and UX rules

`architect`, `frontend-developer`, `reviewer` (under `Focus: ui`), and `tester` (in the browser
check) read this file. Check only the UI that the change adds or changes. A rule of the repository
wins over a rule here: a `CLAUDE.md`, a design system, or a lint config such as
`eslint-plugin-jsx-a11y`.

**Tokens and components.** Use the design tokens of the repository (CSS variables, theme, Sass
variables) for colour, spacing, type, and radius. Never hard-code a colour value when a token
exists. Use an existing component before you make a new one. Name the token source and the
component that you reused.

**Accessibility (WCAG 2.2 AA).**

- Text contrast is at least 4.5:1. Large text is at least 3:1 (1.4.3).
- A control border, an icon, and a focus mark have a contrast of at least 3:1 (1.4.11).
- Each interactive element has a visible focus mark. Never use `outline: none` with no replacement
  (2.4.7).
- A sticky header or other content never hides the focused element completely (2.4.11).
- Each action works with the keyboard, with no trap (2.1.1, 2.1.2).
- Use `button` and `a`. Never use a `div` with a click handler.
- Each input has a label in the code (1.3.1, 4.1.2). A placeholder is not a label.
- An icon-only button has `aria-label` (4.1.2).
- An informative image has `alt` text. A decorative image has `alt=""` (1.1.1).
- Colour is never the only signal (1.4.1).
- A target is at least 24 by 24 CSS px (2.5.8).

**Forms.**

- Each field has a visible label.
- Mark a required field in text.
- Show the error text next to the field. Name the fix. Link the text with `aria-describedby`.
  Announce it with `role="alert"` or `aria-live`.
- Keep the values that the user entered after an error.
- While the form sends, show a busy state and block a second submit.
- Show the result after the submit.

**Responsive layout.**

- Use the breakpoints of the repository.
- At 375 px width, the page has no horizontal scroll, no cut text, and no overlap.
- A touch target is at least 24 by 24 CSS px, or the size of the design system when it is larger.
- Text stays readable at 200% zoom (1.4.4).

**Consistent patterns.**

- Repeated navigation has the same relative order on each page (3.2.3).
- Mark the current page with `aria-current`.
- Each data view has a loading state, an empty state, and an error state.
- The error state gives a retry or a next step.

**Browser check.** These are the steps for `tester`.

1. Call `browser_resize` with width 375 and height 812. Take a screenshot. Check the rules of
   "Responsive layout". Then call `browser_resize` with width 1280 and height 800.
2. Press Tab with `browser_press_key` through the controls that the acceptance criteria name. After
   each press, read `browser_snapshot`. Check that the focus moves in visual order, reaches each
   control, and does not stay trapped. Check on a screenshot that the focused control has a visible
   focus mark.
3. In the snapshot, check that each button, link, and input has a name. Check that each informative
   image has alt text.
4. Submit a form only when the submit changes no data, such as a search form. Never submit a form
   that creates or changes a record. Then check the error text.
5. Report each item as pass or fail, with the evidence, in a list `UI checks`.

**Severity.** These rules are for `reviewer`.

- A finding on a changed element is blocking when it stops a keyboard user or a screen-reader user
  from finishing the task. Examples: a keyboard trap, an action that the keyboard cannot reach, a
  control with no name, a removed focus mark with no replacement.
- A contrast below 4.5:1 on body text is blocking when the token values prove it.
- Every other UI finding is non-blocking.
- A rule that the code cannot show, such as a contrast with an unknown colour value, is Unverified.
