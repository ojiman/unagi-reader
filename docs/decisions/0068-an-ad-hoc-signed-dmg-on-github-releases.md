# 0068 Product 1.0 is an ad hoc signed DMG on GitHub Releases

- Status: valid (approved when its PR is merged; workflow in #432, documents in #433)
- Date: 2026-10-24
- Decider: the owner, in the chat: no paid Developer ID; people download the app from GitHub; the README must show why the app can be trusted.

## Why

Until now the only way to get the app was to build it from source. A signed and notarized app needs the Apple Developer Program (about 99 USD a year), and this is an individual, free project. Without notarization, macOS stops the app on its first launch, and some people will take that as a sign of malware. The answer is not a request for trust: a person can check that the download is the one this repository built, from which commit, and can read why the warning appears.

## Decision

- 1.0 and later versions are published as a DMG on the repository's GitHub Releases. The app is ad hoc signed, not signed with a Developer ID and not notarized.
- The owner pushes a tag `vX.Y.Z`. A workflow on a GitHub-hosted runner builds the Release app from that commit, makes the DMG, and records its SHA-256 and a build provenance attestation. The version comes from the tag.
- The workflow makes a draft release. The owner installs that same DMG on macOS 27, then publishes the draft by hand. No agent and no workflow publishes.
- A published DMG is never replaced. A fix is a new version.
- Updates are by hand: the person downloads the new DMG and replaces the app. There is no automatic update. The library stays where it is (from 1.0 it is kept across updates, specification 7.1).
- The README says why macOS warns, how to open the app with 「このまま開く」 (Open Anyway) in System Settings, and how to check the DMG with `gh attestation verify` or its SHA-256. It does not recommend turning Gatekeeper off or removing the quarantine attribute. Building from source stays available.

The release conditions live in [specification 7.1](../specification.md#71-conditions-to-ship-10).

## Does not include

- Developer ID signing and notarization. A later decision can add them; the earlier research (issue #156) is in Git history.
- Automatic updates, Homebrew, the App Store, the sandbox.

## Limits

Not checked yet: the first-launch dialog of an ad hoc signed app from a DMG on macOS 27; that an update asks for 「このまま開く」 again; `gh attestation verify` on the first release.
