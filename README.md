# Unagi Reader

[![CI](https://github.com/ojiman/unagi-reader/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ojiman/unagi-reader/actions/workflows/ci.yml?query=branch%3Amain)
[![CodeQL](https://github.com/ojiman/unagi-reader/actions/workflows/codeql.yml/badge.svg?branch=main)](https://github.com/ojiman/unagi-reader/actions/workflows/codeql.yml?query=branch%3Amain)

A fast, keyboard-driven RSS reader for macOS that turns the few articles that matter into your own understanding.

> **Status: beta, pre-release.** Requires macOS 27.0 or later. The app's interface is in Japanese only today. There are no prebuilt releases: you build the app from source.

## Why

More articles are written than anyone can read. The hard part is finding the few that matter and turning them into something of your own. Most readers stop at "read" and "starred", and a separate notes app or AI chat breaks the flow of reading.

Unagi Reader is for engineers in 2026 who read many feeds every day. Its value is **one loop in one app, with no waiting: read, take notes, understand.**

- **Read fast.** Sidebar, list and article, with the note beside them, and Vim-style keys. Scrolling and typing never wait on a reload, the network or AI.
- **Note it while you read.** One plain Markdown note, written in your own words next to the article.
- **Bring your own AI.** The app has none of its own. Copy the note as it is and paste it into any AI you like, or use the system's Writing Tools in the note editor. Nothing leaves your Mac unless you paste it.
- **Keep it yours.** No account, no backend, no sync. Everything lives in a local database.

The full statement, with the promises and the questions to ask when in doubt, is in the [vision](docs/vision.md). What the app does, rule by rule, is in the [specification](docs/specification.md).

## Try it

You need a Mac on macOS 27.0 or later and the Swift toolchain from Xcode.

```sh
git clone https://github.com/ojiman/unagi-reader.git
cd unagi-reader
bash scripts/build-app.sh release
open -n '.build/Unagi Reader.app' --args --data-directory /private/tmp/unagi-reader-demo --seed-demo
```

The last command opens a separate instance with synthetic subscriptions and its own data directory, so you can look around without touching a real library. To use the app for real, open `.build/Unagi Reader.app` normally.

The app is ad hoc signed, not notarized. macOS blocks a copy that carries a quarantine attribute (for example, one saved by a browser) until you choose "Open Anyway" in System Settings > Privacy & Security. Building from source avoids this.

## FAQ

**Does it send my data anywhere?** It fetches the feeds you subscribe to, article images and favicons, and original pages when you open them in the app. The app has no AI of its own. Text leaves your Mac only when you copy it and paste it somewhere yourself. There is no backend and no account.

**Where is my data?** In `~/Library/Application Support/UnagiReader/`.

**Will an update break my library?** During the beta, compatibility between versions is not guaranteed. The app shows an error instead of deleting or recreating the library. Back up the `UnagiReader` folder before you update (see the [user guide](docs/user-guide.md#back-up-the-library-by-hand)). From 1.0, saved data is preserved across updates.

**Does it work without AI?** Yes. Everything works with AI turned off.

## Status

- Final product acceptance on a real Mac is not complete.
- [Build, CI and local verification](docs/architecture.md#5-build-and-ci) defines what is checked and what remains unverified.
- Settings has separate app-language and article-translation choices. The UI is available in English, Japanese, Simplified Chinese, Traditional Chinese, Korean, Spanish and Brazilian Portuguese ([specification 3.7](docs/specification.md#37-settings)).

Simplified Chinese, Traditional Chinese, Korean, Spanish and Brazilian Portuguese were prepared with AI and have not been reviewed by a person. To report a translation error, [open an issue](https://github.com/ojiman/unagi-reader/issues/new) with the language, screen, current wording and suggested wording.

## Documentation

| | |
|---|---|
| [Vision](docs/vision.md) | What the product is for, for whom, the promises, and the questions to ask when in doubt |
| [User guide](docs/user-guide.md) | Operations, backup, using the note with another AI |
| [Specification](docs/specification.md) | What V1 does and does not do |
| [Architecture](docs/architecture.md) | How it is built |
| [Roadmap](docs/roadmap.md) | The order of the work |
| [Decision records](docs/decisions/README.md) | Why things are the way they are |
| [AGENTS.md](AGENTS.md) | Development workflow, commands and boundaries |

## Development

Commands are in [AGENTS.md](AGENTS.md#commands); choose checks using [architecture 5](docs/architecture.md#5-build-and-ci). Tests use synthetic RSS/HTML and temporary databases. Claude Code and Codex work on separate issues and PRs under the owner's review.

## Security

CodeQL scans Swift, Python and GitHub Actions code for security issues. A pull request is scanned for Python and GitHub Actions; Swift is scanned on `main` and every week, because its build takes about 20 minutes. Dependabot checks for vulnerable dependencies and opens weekly update pull requests for Swift packages and GitHub Actions. Secret scanning and push protection help detect committed credentials and block pushes containing supported secrets.

The badges above link to the checks on `main`. A successful run means the check completed; it does not guarantee that the app has no vulnerabilities. Technical trust boundaries are documented in the [architecture](docs/architecture.md#2-input-from-the-network-is-untrusted).

Please report potential vulnerabilities privately through the [security policy](SECURITY.md).

## License

[Apache License 2.0](LICENSE). Third-party notices are in [ThirdPartyNotices.md](ThirdPartyNotices.md). Feed content, original pages, site logos and external services remain subject to their owners' rights and terms. The repository contains no personal data, credentials or keys.
