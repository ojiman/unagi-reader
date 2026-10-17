# Roadmap

The **order** of the work to the beta and 1.0, and why. The units of work are [GitHub issues](https://github.com/ojiman/unagi-reader/issues); how they are written and taken is in [AGENTS.md](../AGENTS.md). The value is in the [vision](vision.md), the product in the [specification](specification.md).

## Now: the beta

**What the beta is for** (a draft by the agent, 2026-10-14; the owner confirms or rewrites it): the first build that someone other than the owner uses. It answers one question: does the loop (read → note → understand) hold for an engineer who reads many feeds, without the owner beside them? What we want back: where they waited (specification 2.1), where they had to manage or decide something (vision, question 2), and whether they still write in the note after a week. Who, and how many: the owner decides.

Everything that must be done before the beta is an issue in the milestone [Beta](https://github.com/ojiman/unagi-reader/milestone/1). It is closed to new issues; only the owner adds to it. **The beta is done when every issue in it is closed.**

1. **Real-device check by the owner:** [#136](https://github.com/ojiman/unagi-reader/issues/136), [#145](https://github.com/ojiman/unagi-reader/issues/145), and a dogfooding week. Bugs found here come before any polish.
2. **Preparation:** [#142](https://github.com/ojiman/unagi-reader/issues/142) a fresh acceptance run.
3. **Other conditions:** the owner decides how the beta is signed and published ([findings](superpowers/plans/2026-10-14-beta-distribution.md), section 6).

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

## Before 1.0

The conditions in [specification 7.1](specification.md). A prune of the documents before the release (the second pass was done on 2026-10-14).

## Done

- V1 specification approved by the owner on 2026-10-17 ([#144](https://github.com/ojiman/unagi-reader/issues/144)); see the [specification](specification.md).
- V1 simplification (decision 0019), stages S1 to S5; parts later removed by decision 0049. Rename to Unagi Reader (0023).
- One note, no AI of its own (decision 0049): [#115](https://github.com/ojiman/unagi-reader/pull/115), [#116](https://github.com/ojiman/unagi-reader/pull/116), [#118](https://github.com/ojiman/unagi-reader/pull/118), [#119](https://github.com/ojiman/unagi-reader/pull/119), [#122](https://github.com/ojiman/unagi-reader/pull/122).
- Layout and motion (0044, 0046 to 0048), subscriptions (0036 to 0041, 0043, 0053), name and icon (0051).
- Documents in English and pruned; budgets for no waiting (2026-10-14).
