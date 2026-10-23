# 0065 CI guards main; product behavior is verified locally

- Status: valid (owner-approved; implementation in #396)
- Date: 2026-10-23
- Decider: the owner, accepting the CI/local split and the narrowed failure/verification rules in the chat.
- Replaces: 0007. Its version floors are unchanged; the old record is in Git history.

## Why

The person uses macOS 27. CI builds on 26.6. Native layout and time-sensitive checks on both systems added investigation work without establishing the supported product's behavior. The former phrase “build and regression tests” did not define which UI assertions belonged in CI.

The reading loop benefits from useful regressions and shorter feedback, not repeated full verification on two operating systems. Removing checks from CI must not remove storage/recovery coverage or lower the product's performance budgets.

## Decision

- Keep build floor 26.6, support floor 27.0 and the existing SDK restriction. CI checks compilation, logic regressions, documents and packaging/signature. It does not run the real-app UI smoke suite, native geometry/pixel assertions or real-time performance budgets.
- When GitHub provides macOS 27 runners, raise the build floor and CI to 27 in a separate PR.
- Product layout, feel and performance evidence comes from local macOS 27. Retain the excluded tests and the full local command. Select routine local checks by the change's risk; do not require all tests and all packaged checks for every small change.
- A 26-only rendering or timing failure is not evidence of a supported-product defect. A build, storage, recovery or logic failure is not dismissed on the basis of its OS, and a red test is not automatically excluded.
- Keep `check` as the required gate. The owner reviews and merges. Screen changes still need relevant local verification; failed or unverified checks are reported as such.

The operational rule and verification scope live in [architecture 5](../architecture.md#5-build-and-ci). Other guides link there rather than defining another copy.

## Limits

Local verification carries more responsibility. #387 and #392 track synthetic-launch safety and reliable local smoke startup; this change does not repair them. #388–#391 are assessed on 27 before proposing closure, not silently treated as fixed. Input methods, accessibility and long use remain owner checks (#145). Performance budgets in specification 2.1 are unchanged.
