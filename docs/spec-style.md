# How to write the specification

The specification (`docs/specification.md`) is read by people and, more and more, by AI agents that start with nothing but the repository. Write it so that an agent that reads only the relevant part builds the right thing. These rules are short on purpose.

## The layers: one fact in one place

| Layer | Where | Answers | Not for |
|---|---|---|---|
| Intent | `docs/vision.md` (the owner's words) | Why does the product exist? What to ask when in doubt? | Behavior |
| Behavior | `docs/specification.md` | What does the person see and do? What is never built? | How it is built, the history |
| Design | `docs/architecture.md` | How is it built? | Behavior the person sees |
| Decisions | `docs/decisions/` | Why is it so? What was tried? | The current rules (they are copied into the specification) |
| Guide, README | `docs/user-guide.md`, `README.md` | How to use it | Defining behavior: they follow the specification |

A rule is written in one place. Other documents link to it. If a decision changes behavior, the same pull request changes the specification; the decision is cited at the end of the rule as a link, not told as a story.

## How a rule is written

1. **Model first.** A section starts with the model: what the parts are called and what states they can be in (a table or a small picture), then the rules. An agent builds the right structure from the model, not from rules scattered in paragraphs.
2. **One rule, one sentence, in a list or a table.** No paragraph that holds ten rules. Numbers, sizes and times are written out (for example 0.3 s, 280 to 640 pt).
3. **Observable.** A rule says what the person sees or what must never happen, in words that a test or a person on a real Mac can check. The acceptance scenarios (section 7 of the specification) check the sections above them; a test names the scenario it checks in a comment (`// PRD-04`). "Smooth" is a number: the budgets of section 2.1.
4. **A status on a rule that is not built yet.** `[not built #issue]` (or `[not measured #issue]` for a budget). The specification may be ahead of the code; the mark says where. Remove the mark when the work lands (the documents check fails when the issue is closed). A rule with no mark is built.
5. **One name for one thing.** The specification keeps a glossary (section 3.0, and the areas in 3.1.1): the label the person sees, what it means, and the place in the code (for example list = `NativeArticleList`). The code names are the link. Use the same word everywhere ("original page", not "original" in one place and "original page" in another). Quote UI labels exactly (Language, below).
6. **What is not built, next to the feature.** An agent builds what is not written if it seems kind. A short "not now" line near each feature is worth more than a list at the end.
7. **Questions are marked as questions.** An undecided point is listed as one (with the issue), not hidden in a sentence.
8. **A picture for layout.** A layout is drawn (a plain text sketch is enough) next to the table of its states.

## Size and files

A section should fit in one screen of reading. A rule that grows into a paragraph becomes a list. When a section is too big, split it into sub-sections with their own numbers. Move a whole area into its own file only with a pull request that fixes every link to it; numbers such as 3.3 and PRD-04 are cited by other documents.

## Language

English (AGENTS.md, Language). The labels the person sees are quoted exactly in their English source text from the String Catalog: a button, pane or option in bold, a menu path as File ▸ Import OPML…, a message or VoiceOver text in quotation marks. Names that point at code are written as they are in the code.
