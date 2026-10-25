# Roadmap

The **order** of the work after 1.0, and why. The units of work are [GitHub issues](https://github.com/ojiman/unagi-reader/issues); how they are written and taken is in [AGENTS.md](../AGENTS.md). The value is in the [vision](vision.md), the product in the [specification](specification.md).

## Now: after 1.0.0

1.0.0 was published on 2026-10-25 on [GitHub Releases](https://github.com/ojiman/unagi-reader/releases/tag/v1.0.0) (tag `v1.0.0`, commit 644a805). The owner uses it every day; problems found in real use come before any polish and ship as 1.0.x releases.

From 1.0, an update keeps the person's library: CI opens a library written by `v1.0.0` on every code change ([specification 7.1](specification.md#71-conditions-to-ship-10)). A release is a tag `vX.Y.Z` on `main`, built by CI as a draft that the owner checks and publishes ([decision 0068](decisions/0068-an-ad-hoc-signed-dmg-on-github-releases.md)).

## Next

Nothing is scheduled.

## Candidates

Ideas: no order, no issue. When the owner decides to build one, it moves to Next with an issue; when it is dropped, to Not planned.

- The same size scale for the note editor (needs a real Japanese input check).
- A draft helper from an AI outside the Mac, with the person's own key (needs a new decision).
- A time zone setting.
- More styling in the note editor: tables, check lists, a preview.
- More than one note; note folders, search and tags (0049 chose one note).
- Passing part of the note to an AI; system sharing services; a view of past days; copying the URL.

## Not planned

Goals and learning plans; AI suggestions of notes; AI editing of the note; sync and accounts; a settings framework; key remapping.

## Done

- 1.0.0 published on 2026-10-25: an ad hoc signed DMG on GitHub Releases, built by CI from the tag `v1.0.0` (decision 0068, [#432](https://github.com/ojiman/unagi-reader/issues/432)), with the README and user documents for it ([#433](https://github.com/ojiman/unagi-reader/issues/433)). The milestone [1.0](https://github.com/ojiman/unagi-reader/milestone/1) is complete.
- 1.0 shipping conditions (specification 7.1): the frozen schema [#449](https://github.com/ojiman/unagi-reader/issues/449), the CI check from `v1.0.0` [#450](https://github.com/ojiman/unagi-reader/issues/450), and the fixed values with the beta library and real-Mac update checks [#451](https://github.com/ojiman/unagi-reader/issues/451) (the owner's check with the draft DMG passed on 2026-10-25).
- Real-device check [#145](https://github.com/ojiman/unagi-reader/issues/145) closed; remaining checks moved to #451.
- V1 specification approved by the owner on 2026-10-17 ([#144](https://github.com/ojiman/unagi-reader/issues/144)); see the [specification](specification.md).
- V1 simplification (decision 0019), stages S1 to S5; parts later removed by decision 0049. Rename to Unagi Reader (0023).
- One note, no AI of its own (decision 0049): [#115](https://github.com/ojiman/unagi-reader/pull/115), [#116](https://github.com/ojiman/unagi-reader/pull/116), [#118](https://github.com/ojiman/unagi-reader/pull/118), [#119](https://github.com/ojiman/unagi-reader/pull/119), [#122](https://github.com/ojiman/unagi-reader/pull/122).
- Layout and motion (0044, 0046 to 0048), subscriptions (0036 to 0041, 0043, 0053), name and icon (0051).
- Documents in English and pruned; budgets for no waiting (2026-10-14).
