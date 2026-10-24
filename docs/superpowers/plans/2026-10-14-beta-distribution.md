# Beta distribution: what signing, notarization and a release need

- Status: historical beta-distribution research for the owner (issue #156). The current release goal is product 1.0 ([roadmap](../../roadmap.md), the owner, 2026-10-24). The proposals below are not an approved release plan. Nothing was signed, notarized, uploaded or published. Deleted when the release issues it proposes are closed.
- Date: 2026-10-14
- Sources: Apple's pages read on 2026-10-14: [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Developer ID](https://developer.apple.com/developer-id/), [Compare memberships](https://developer.apple.com/support/compare-memberships/). The body of the notarization page did not load in the reader used (only its title), so its steps (sections 2.3 to 2.6) are from general knowledge. Facts marked **(check)** were not read on Apple's pages today; check them before acting.

## 1. Where the app is today

- `scripts/build-app.sh` builds the `.app` by hand (no Xcode project) and signs it **ad hoc** (`codesign --sign -`). No hardened runtime, no entitlements file, no sandbox.
- The version is written into `Info.plist` by the script: `CFBundleShortVersionString` 0.2.0, `CFBundleVersion` 2, both fixed strings. CI's `release` job makes the same ad hoc build and checks the signature after a ZIP round trip.
- A copy downloaded with a browser carries the quarantine attribute, and macOS blocks it until the person chooses "Open Anyway" in System Settings > Privacy & Security (README).

## 2. What a signed and notarized build needs

1. **Apple Developer Program membership.** Developer ID certificates are created only by members, and only by the team's **Account Holder** (Developer ID page). The free account does not offer it (Compare memberships). The fee is 99 USD a year, varying by region **(check)**.
2. **A Developer ID Application certificate**, made in Xcode or in Certificates, Identifiers & Profiles. It stays in the owner's keychain; per AGENTS.md it is never given to an agent or to CI unless the owner decides so.
3. **Sign with the hardened runtime and a secure timestamp** (notarization requires both **(check)**):
   `codesign --force --options runtime --timestamp --sign "Developer ID Application: <name> (<team>)" "Unagi Reader.app"`.
   Entitlements: none expected. The app does not use JIT, and the web view runs in WebKit's own processes **(check by notarizing once and running the app)**. It is not sandboxed. Sandboxing is not required outside the App Store **(check)**, and adding it would change where the library lives, so it is a separate decision.
4. **Notarize**: zip the app (`ditto -c -k --keepParent`), then `xcrun notarytool submit <zip> --keychain-profile <profile> --wait`. The profile is stored once with `xcrun notarytool store-credentials` (an app-specific password or an App Store Connect API key). On a rejection, `xcrun notarytool log <id>` says why.
5. **Staple** the ticket to the app, so it opens offline: `xcrun stapler staple "Unagi Reader.app"`, then `xcrun stapler validate`. A `.zip` cannot be stapled; staple the `.app`, then zip it again (or ship a `.dmg`, which can be stapled) **(check)**.
6. **Check**: `spctl --assess --type execute --verbose=4 "Unagi Reader.app"` should say it is accepted, from a notarized Developer ID.

**How `build-app.sh` would change:** a third mode, for example `build-app.sh beta`. It builds `release`, then signs with the Developer ID (the identity is read from an environment variable, never stored in the repository) and `--options runtime --timestamp`. A separate script notarizes and staples, so that CI never needs the certificate. The ad hoc path stays for local and CI builds.

## 3. Giving the beta to people

- **Package:** a `.zip` of the stapled app, attached to a GitHub release marked as a pre-release. A `.dmg` is nicer to look at but is one more step to sign and notarize; the zip is enough for a few testers.
- **First launch:** a notarized app downloaded from the internet still shows the system's one-time question ("downloaded from the Internet, are you sure you want to open it?") with Open and Cancel **(check)**. There is no trip to System Settings any more.
- **Updates:** none in the beta. A new build is a new release; the tester downloads it and replaces the app. Beta data is not kept between betas (decision 0003), so the release notes must say so plainly.
- **Who gets it:** the owner decides; see the [roadmap](../../roadmap.md) for the current release goal. A public release page or a private link is the owner's choice. GitHub release assets of a public repository are public.

## 4. Version and build numbers

- Today both are fixed strings in `build-app.sh`. Proposal: `CFBundleShortVersionString` is plain numbers such as `0.3.0`, because the key takes up to three integers separated by periods **(check)**, so "Beta 1" goes in the release title, not the version. `CFBundleVersion` is a number that only grows, for example the count of commits on `main` (`git rev-list --count HEAD`), set by the script.
- The owner sets the version when they decide to release; the script fills the build number. The CI's ad hoc build keeps a visible difference: it is not signed with the Developer ID, so `spctl` rejects it.

## 5. Cost and order

| Step | Who | Time (rough) |
|---|---|---|
| Join the Developer Program, if not a member | the owner (Account Holder) | a day or two for Apple's checks **(check)**; 99 USD a year |
| Create the Developer ID Application certificate | the owner | minutes |
| `build-app.sh beta` and a notarize script (no secrets in the repository) | an agent, in a PR | one PR |
| First signed, notarized build; check on a clean Mac account | the owner | an hour |
| A GitHub pre-release with the zip and the notes | the owner, or an agent on the owner's instruction | minutes |

## 6. What the owner must decide

1. Join (or use) the Developer Program, and who holds the certificate (the owner's Mac only, or also CI with a secret). Recommendation: the owner's Mac only for the beta.
2. Zip or disk image. Recommendation: zip.
3. Where the beta is published (a public GitHub pre-release or a private link) and to whom.
4. The version name of the first beta.

## 7. Release issues to open after the decisions

1. `build-app.sh beta`: Developer ID signing with the hardened runtime and a timestamp; the build number from Git; no identity in the repository.
2. A notarize-and-staple script with its test (`scripts/test-*.sh`), run on the owner's Mac.
3. The release notes template: what the beta is for, that data is not kept between betas, how to report, how to remove the app and its data.
4. The README and the user guide: how to install the signed beta (and remove the "Open Anyway" text once the beta is signed).

## Not verified

Everything marked **(check)**; whether the app needs any entitlement under the hardened runtime (only a real notarization and launch will tell); the first-launch dialog on macOS 27.
