# Independent review checklist

For reading a fixed commit and finding the gap between what a change **claims** and the **evidence** for it. A review by the same kind of agent that wrote the change shares its blind spots, so decide what to look at first, and write down what you saw and what you did not. It works the same for Codex and Claude Code. When it applies is in [AGENTS.md](../AGENTS.md#definition-of-done).

## 1. Claim and evidence

- Each "verified" or "PASS" has a command, an environment (OS, Xcode / Swift) and a commit. Evidence from another commit or environment does not count.
- A document or the README describes a behavior (for example "an old database shows a startup error"): is it measured or guessed? Does the test check that behavior, or a nearby input?
- Unverified never became PASS. A skipped job (a docs-only PR, `release` that was not due) and a skipped opt-in test (no fixture set) are not a pass.
- A test run counts only if it finished: the summary line is there and every started test ended (`scripts/check-test-log.sh`). An exit code of 0 with no summary is not a pass.
- Where the specification has an acceptance scenario for the change (`PRD-nn`), a test names it (`// Checks PRD-nn`) and really checks it.

## 2. A requested save or change reported as done when it failed

- A save or reload failure dropped by `try?`; text the person typed, dropped because its target is gone; the state right after a failed save or reload.
- After a failure, retry: do the screen and the database agree? After a restart?
- A new or changed mutating path has a save-failure and reload-failure test (read state, subscriptions, Star, note, retention included). It calls `reloadIfNeeded()` first and resolves models by ID.
- These are normal no-ops; do not flag them: cancellation, a stale async answer after the selection moved, an optional action with nothing to act on. Check that the code or the PR tells them apart from a failure.
- Example: in PR #10, when a reload also failed right after a failed save, one path changed a model of the old context and returned success.

## 3. Does the result depend on the environment?

- Judge CI and local evidence by their roles in [architecture 5](architecture.md#5-build-and-ci). Were the checks appropriate to the change, and were unverified product behaviors kept explicit? See also the known gotchas in [AGENTS.md](../AGENTS.md#known-gotchas).
- Does it grow `ReaderView`'s modifier chain, call `NSButton.performClick` in a hosted test, or add a hosted test that folds columns outside `SplitViewFoldTests`? Those are in the same list.

## 4. Scope, decisions and the documents

- One theme per PR. A bug fix is not bundled with polish. "Not included" is written.
- A change of behavior or policy changes the specification (and the architecture) in the same PR. A decision record is there only when a policy, or what a person can do or rely on, changed; its Status is not stronger than the facts, and a record it replaces says so.
- A document PR removes what it replaces and does not repeat a rule that has a home. `python3 scripts/check_docs.py` passes.
- A user-reported symptom was reproduced before it was called fixed.
- A change that can make the reader wait is checked against the budgets of specification 2.1 (measured, or listed as not measured).

## 5. Data and outside writes

- It does not touch the person's library, credentials or browser profile; its input is synthetic.
- Adding a dependency, pushing, publishing and signing are within the owner's instruction.

## Writing the result

- A finding has: severity, place, a concrete scenario in which it fails, and a suggested fix.
- "No findings" says which of 1 to 5 were checked, over which commits, and which were not.
- Say which tests were not run and which environments were not seen.
