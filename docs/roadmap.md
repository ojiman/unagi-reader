# Roadmap

The **order** of the work toward product 1.0, and why. The units of work are [GitHub issues](https://github.com/ojiman/unagi-reader/issues); how they are written and taken is in [AGENTS.md](../AGENTS.md). The value is in the [vision](vision.md), the product in the [specification](specification.md).

## Now: v1.0.0

The owner uses the app daily and fixes problems found there. The `v1.0.0` tag has been pushed, CI has created the draft release, and the shipping conditions are complete. The owner publishes the draft.

The milestone [1.0](https://github.com/ojiman/unagi-reader/milestone/1) tracks required release work. **1.0 is ready when its milestone issues and the shipping conditions below are complete.** Next and Candidates are not automatically required for 1.0.

1. **Shipping conditions:** [specification 7.1](specification.md#71-conditions-to-ship-10), including data preservation across updates from 1.0. All are met.
2. **Distribution:** an ad hoc signed DMG on GitHub Releases, built by CI from a tag ([decision 0068](decisions/0068-an-ad-hoc-signed-dmg-on-github-releases.md)). The owner publishes the `v1.0.0` draft.

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

- 1.0 shipping conditions (specification 7.1): the frozen schema [#449](https://github.com/ojiman/unagi-reader/issues/449), the CI check from `v1.0.0` [#450](https://github.com/ojiman/unagi-reader/issues/450), and the fixed values with the beta library and real-Mac update checks [#451](https://github.com/ojiman/unagi-reader/issues/451) (the owner's check with the draft DMG passed on 2026-10-25).
- Real-device check [#145](https://github.com/ojiman/unagi-reader/issues/145) closed; remaining checks moved to #451.
- V1 specification approved by the owner on 2026-10-17 ([#144](https://github.com/ojiman/unagi-reader/issues/144)); see the [specification](specification.md).
- V1 simplification (decision 0019), stages S1 to S5; parts later removed by decision 0049. Rename to Unagi Reader (0023).
- One note, no AI of its own (decision 0049): [#115](https://github.com/ojiman/unagi-reader/pull/115), [#116](https://github.com/ojiman/unagi-reader/pull/116), [#118](https://github.com/ojiman/unagi-reader/pull/118), [#119](https://github.com/ojiman/unagi-reader/pull/119), [#122](https://github.com/ojiman/unagi-reader/pull/122).
- Layout and motion (0044, 0046 to 0048), subscriptions (0036 to 0041, 0043, 0053), name and icon (0051).
- Documents in English and pruned; budgets for no waiting (2026-10-14).
