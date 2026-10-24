# Unagi Reader development

Instructions for coding agents (Claude Code, Codex) and the person who reviews them: where things are, how to verify, where the boundaries are. Keep it short; details live in the linked documents. This is the only instruction file: Claude Code reads `AGENTS.md` directly (v2.1.277 or later), so there is no `CLAUDE.md`.

## Where things are

| Path | Role |
|---|---|
| docs/vision.md | Why the product exists, for whom, the promises, the questions to ask when in doubt. Above everything else. |
| docs/specification.md | What V1 is and is not, as the person sees it. The source of truth for behavior. |
| docs/spec-style.md | How to write the specification. |
| docs/architecture.md | How it is built, and the technical contracts a change must keep. |
| docs/decisions/ | Who decided what and why. Read when you need the reason for a rule. |
| docs/roadmap.md | The order of the work. Units of work are GitHub issues. |
| docs/user-guide.md, README.md | How to use it. They follow the specification and define nothing. |
| docs/review-checklist.md | The lens for an independent review of a fixed commit. |
| SECURITY.md | How to report a vulnerability (privately), and what to expect. |
| docs/verification/ | Evidence for a few risky changes. Logs, not rules. |
| Sources/ReaderCore, Sources/UnagiReader | The core (no UI) and the SwiftUI / AppKit app. |
| Tests/ | Tests, synthetic data only. A test that checks an acceptance scenario says so in a comment (`// PRD-04`). |
| scripts/ | Build, CI gate and checks; each `x.sh` has a `test-x.sh`. |

## Commands

```sh
test_log=$(mktemp /private/tmp/unagi-reader-tests.XXXXXX)
swift test --scratch-path /private/tmp/unagi-reader-dogfooding-build > "$test_log" 2>&1 &&
    bash scripts/check-test-log.sh "$test_log"                            # local tests; read "$test_log" for the output
local_log=$(mktemp /private/tmp/unagi-reader-local-tests.XXXXXX)
swift test --scratch-path /private/tmp/unagi-reader-dogfooding-build --filter "$(bash scripts/ci-gate.sh local-tests)" --xunit-output "$local_log.xml" > "$local_log" 2>&1 &&
    bash scripts/check-test-log.sh "$local_log" "$local_log-swift-testing.xml" # CI-excluded tests; scope in architecture 5
bash scripts/build-app.sh release                                        # ad hoc signed .build/Unagi Reader.app (debug is the default)
bash scripts/make-dmg.sh '.build/Unagi Reader.app' <new>.dmg              # the release disk image and its .sha256 (test: scripts/test-make-dmg.sh)
bash scripts/fetch-ci-app.sh <PR number>                                  # a PR's CI-built app, without the quarantine attribute (needs gh)
bash scripts/make-synthetic-copy.sh                                      # copies the built app with a synthetic bundle ID; prints the launch command
bash scripts/test-make-synthetic-copy.sh                                 # copy, path refusal and failure checks (no app is launched)
bash scripts/run-ui-smoke.sh                                            # real-app XCUITest; build the app first, needs a logged-in desktop
bash scripts/test-run-ui-smoke.sh                                       # synthetic feed and result-check tests; no app is launched
git diff --check
python3 scripts/check_docs.py                                          # links, decision numbers and statuses, PRD tags (--online: closed issues in marks and the roadmap)
bash scripts/test-check-docs.sh
```

- **For a manual synthetic run, use the command printed by `make-synthetic-copy.sh`.** It takes the built app (or an app path as its first argument), makes a temporary copy with its own bundle ID and a new data directory, and does not launch it. An optional second argument names a new data directory; the real library and its symlink aliases are refused. The printed command needs `open -n`: without it, `open` can reuse a running Unagi Reader and drop `--args`. Before touching anything, check that the process has the temporary `--data-directory` (`pgrep -fl UnagiReader`) and that the window shows the synthetic subscriptions.
- **Verification scope:** choose checks by the change using [architecture 5](docs/architecture.md#5-build-and-ci). The full Swift command above includes local-only tests; it is not a requirement for every small change. For real-app smoke, build Release and run `scripts/run-ui-smoke.sh` locally on macOS 27. Synthetic launch instructions above still apply.
- **Opt-in store checks** (not in CI during the beta): `bash scripts/prepare-v1-store-fixture.sh <new dir>`, then `UNAGI_READER_V1_FIXTURE_DIR=<dir> swift test …`. The other fixtures are in architecture 3.
- **CI and version floors:** [architecture 5](docs/architecture.md#5-build-and-ci) defines the jobs, what they prove, SDK limits and local product verification. [README Security](README.md#security) describes the separate security scans.

## How work is tracked

- **The roadmap** is the order, short, with links. **An issue** is a unit of work someone can start today and know when it is done: Problem, Acceptance Criteria, Constraints, Out of scope. A bug, tech debt or a question for the owner is an issue at once. **An idea** is one line in the roadmap's candidates. Work in none of these is not tracked: open an issue instead of leaving a note in a chat or a PR.
- **One issue, one pull request, `Fixes #n`.** Say that you take it. An issue with an open question for the owner waits for the answer.
- **PR titles start with the kind:** `feat:`, `fix:`, `refactor:`, `test:`, `docs:` or `ci:`.
- **A bug found on the way** becomes a new issue, not a bigger PR. For a single UI or timing-sensitive failure on the shared Mac, see the next rule. A **security hole** does not go in a public issue ([SECURITY.md](SECURITY.md)); tell the owner, who reports it as a private advisory.
- **Test observations on the shared Mac:** record a single UI or timing-sensitive failure, its command, result and context in the PR, or in the chat if there is no PR. Do not create an issue from that observation alone or assume interference caused it. Prefer focused rechecks under [Writers at the same time](#writers-at-the-same-time). Open issues for demonstrated product impact or repeated failures in such runs that block needed verification; clearly harmful defects need no repeat. A successful recheck can verify the changed operation; keep the earlier failed run accurate. Unrelated failures do not undo separately verified operations. Filing an issue does not complete verification.
- **Labels say who writes and what can run beside what.** `codex` marks an issue that Codex writes; any other issue is Claude Code's. `area:no-screen` touches no screen: it can run beside screen work. `area:reader-view` touches `ReaderView.swift` and its long modifier chain: one at a time. `area:store` touches `ReaderStore`, retention or the models: one at a time. `no-spec` marks an enhancement that needs no specification entry.
- **Where PRs collide:** `ReaderView.swift`, the store, the end of the decision index, and decision numbers (take the next free number when you open the PR; renumber if `main` moved).
- **The milestone 1.0** is closed to new issues; only the owner adds to it.
- **A plan** for work of several PRs goes to `docs/superpowers/plans/` and is deleted when its last PR merges.

## Writers at the same time

Several writers may work at once ([decision 0062](docs/decisions/0062-several-writers-under-review.md)); these rules keep that safe.

- **Each writer has its own issue, branch and worktree.** The owner reviews and merges. A writer merges only when the owner has said so for that PR, in the chat or on the PR; the rule below still applies. Dependabot's PRs are never merged by a writer (Boundaries).
- **No second PR on files an open PR touches.** At most three writers' PRs are open at once (Dependabot's are not counted).
- **A measurement or a real-app test runs alone on the Mac**, with no other build or test running. A number measured beside another run is not recorded.
- **The `main` ruleset needs a PR, `check` and an up-to-date branch.** After another PR merges, bring your branch up to date and wait for `check` again before the owner merges.

## Starting or resuming

A new thread has no memory of the last one. Rebuild the state from Git and GitHub, not from a summary: the branch, HEAD, uncommitted changes, open PRs, the latest CI result on `main` (`gh run list --workflow ci.yml --branch main`) and relevant local verification, the relevant part of the specification. Say what is done, what is not, and the next step before changing anything. Reuse an earlier PASS only for the same commit and environment.

## Boundaries

- Tests use synthetic RSS / HTML and temporary databases. Never read the person's library, credentials, Keychain, browser profile or other projects. `/private/tmp` is scratch, not a security boundary.
- GitHub only through the host's signed-in `gh`; never read, copy or pass a token. An Apple ID, certificates and signing keys are never given to an agent.
- Local edits, tests, builds and commits are allowed. Check concrete URLs, dependencies, migrations and external writes against the person's current instruction; what the task already allows need not be asked again.
- Never: read credentials, a destructive `reset` or `clean`, `sudo`, turning the sandbox off, running an outside script. Do not use subagents as a habit; never give a child agent the whole conversation, the person's data or credentials.
- Never push to `main`. Never sign, submit or publish an app without the owner's instruction. A new or changed dependency (SwiftSoup is pinned exactly) needs the owner's instruction. Dependabot opens update PRs every week for the Swift packages and the GitHub Actions (`.github/dependabot.yml`; CodeQL's actions come as one PR, because init and analyze must share a version); they are changed dependencies, so do not merge one yourself. Read the change and its CI result, and leave the decision to the owner. Their titles ("Bump …") are exempt from the PR title rule.
- No unattended workers, and do not resume the Keychain probe. Every writer keeps these boundaries; the sandbox of each agent is the owner's setting, and this file does not enforce it. A reviewer reading a fixed commit is not "read-only isolation" because a prompt says so.
- `docs/vision.md` is the owner's words; change it only on the owner's instruction. Check every feature against its four questions.
- Data: no compatibility between betas, saves within one version are kept, from 1.0 nothing is lost ([decision 0003](docs/decisions/0003-beta-data-compatibility.md), specification 7.1). Never delete an unreadable store automatically.

## Definition of done

Always:

1. One theme per PR. Bugs the owner reported come before polish. Say what the PR does not include.
2. A bug is reproduced by a failing test first; the PR records both results.
3. Unverified behavior is never written as PASS (macOS 27.0, input methods, VoiceOver, Reduce Motion, long use). The PR lists what it leaves unverified.
4. A change of behavior or policy changes the specification or the architecture in the same PR. When the owner **decides** a behavior before it is built, write it in the specification the same day with `[not built #n]` (a docs PR of its own) and let the issue link to that section; a decision left in an issue comment is lost. CI enforces it: every open `enhancement` of the milestone 1.0 must be named by a mark in the specification, or carry the label `no-spec` (it changes nothing the person sees). The PR that closes the issue (`Fixes #n`) removes its mark and its roadmap line; the check treats that issue as done. A **decision record** only when a policy, or what a person can do or rely on, changes; layout, sizes, timings and wording go to the specification only.
5. A save or change the person asked for is never reported as done when it was not (`try?` that drops a failure; text lost because its target is gone). Cancellation, a stale async answer and an action with nothing to act on are legitimate no-ops; keep them distinct.
6. **A document PR removes what it replaces.** When you add a rule, delete the old wording in the same PR; do not repeat a rule that has a home (vision, specification, architecture, this file) — link to it. A PR that only adds text says why.

Verification by risk is defined in [architecture 5](docs/architecture.md#5-build-and-ci).

Evidence stays small: a verification record only for a risky change or a PASS that 1.0 relies on, at most one per PR, the result in the first three lines. No raw logs or probe code in the repository. A low-risk review is one pass.

## Language

The chat with the owner is in Japanese; everything else is in English (the owner, 2026-10-14). Plain English: short sentences, common words, the same term for the same thing. The app's String Catalog uses English source text; documents quote the Japanese labels exactly, with a short gloss when it helps. Old decision records and old commits stay as they are.

## Known gotchas

- macOS 26: after a failed save, registered models can keep unsaved values. Use `ReaderStore.rollback()`, resolve models by ID, and call `reloadIfNeeded()` first in any new mutating method (architecture 3.1).
- The CI compiler (Swift 6.3.3) crashed on an actor-isolated method reference passed as a `Binding` setter; use an explicit closure (PR #14).
- The CI compiler (Swift 6.3.3, Debug) aborted the process in `swift_task_dealloc` ("freed pointer was not the last allocation") when a task called an async throwing closure written as a default argument of `init` and that call threw on cancellation (#266). The same closure passed by a caller was fine. Call the real function directly in the task; keep injectable closures optional for tests.
- The CI compiler gave up type-checking when `ReaderView`'s modifier chain grew (PR #96; local Swift 6.4 was fine). The chain is now short stages (`splitView`, `readerLifecycle`, `readerKeys`, `readerPresentations`, `reader`; #132): add a modifier to the stage it belongs to, or start a new stage. Window-level modifiers stay outside, as a `ViewModifier` in `body` (as `OPMLImportPresentation`).
- A view that comes and goes with a column fold and carries `.ignoresSafeArea` itself made the layout loop until AppKit raised an exception, in narrow windows (#222, the filter bar). Put the modifier on a container that stays. A hosted test cannot show it; run the packaged app at about 1,170 pt, open the note and press the layout button.
- A hosted UI test must not call `NSButton.performClick`: its nested event loop can stop the run loop, and the test process ends with exit code 0 and no summary line. Drive the app with the key handlers (`NativeArticleList.Table.keyHandler`). Use the checked local command above too: exit code 0 alone is not a pass. Write output directly to the log, not through `tee` (#186). Run a changed UI suite several times. Evidence and limits: [UI test completion](docs/verification/ui-test-completion.md).
- Hosted tests that fold split view columns run one after another, under `SplitViewFoldTests` (`Tests/ReaderUITests/ReaderLayoutTests.swift`).
- Three problems showed only in CI (PR #10 SwiftData rollback, PR #12 the packaged app's signature, PR #14 the compiler). Local success is necessary, not sufficient.
