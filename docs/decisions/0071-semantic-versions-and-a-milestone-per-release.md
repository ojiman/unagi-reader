# 0071 Semantic versions, and a milestone per release

- Status: valid (approved when its PR is merged)
- Date: 2026-10-25
- Decider: the owner, in the chat: after 1.0.0, bug fixes ship as 1.0.1 and small features as 1.1.0.

## Why

1.0.0 was published on 2026-10-25. Until then one milestone, "1.0", listed the required work, and the rules and the documents check named it. A person who sees a new version should be able to tell what kind of change it is, and the owner needs one place per release that says what it must contain.

## Decision

- A version is `MAJOR.MINOR.PATCH` ([semantic versioning](https://semver.org/)), and the tag is `vMAJOR.MINOR.PATCH` (decision 0068).
  - **PATCH** (1.0.1): bug fixes only.
  - **MINOR** (1.1.0): features or changes that keep what a person relies on.
  - **MAJOR** (2.0.0): a break, for example a higher macOS floor or a feature taken away.
- In every case the library is kept across the update (specification 7.1, decision 0003). No version may break that.
- Each release has a GitHub milestone named by its version. The owner creates it when it is needed and is the only one who adds issues to it. A release is ready when its milestone has no open issue and the conditions of specification 7.1 hold.
- The milestone is the only list of a release's issues. The roadmap points to the milestones and does not repeat their issues (the owner, #456).
- The documents check applies to every open milestone: an open `enhancement` in one needs a status mark in the specification, or the label `no-spec`.

## Does not include

- Release dates or a schedule.
- Pre-release versions (`-beta.1`); the release workflow accepts only `vX.Y.Z`.
