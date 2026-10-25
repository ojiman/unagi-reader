#!/usr/bin/env python3
"""Tests for scripts/check_docs.py. Needs only Python 3 (no network: the issue states are given by hand)."""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_docs  # noqa: E402


def write(root, relative, text):
    path = os.path.join(root, relative)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


class LinkTests(unittest.TestCase):
    def test_a_broken_relative_link_is_reported_with_its_line(self):
        with tempfile.TemporaryDirectory() as root:
            write(root, "docs/a.md", "first\nsee [b](b.md) and [gone](gone.md#x)\n")
            write(root, "docs/b.md", "ok\n")
            problems = check_docs.link_problems(root)
            self.assertEqual(len(problems), 1)
            self.assertIn("docs/a.md:2", problems[0])
            self.assertIn("gone.md", problems[0])

    def test_outside_links_anchors_code_blocks_and_inline_code_are_not_checked(self):
        with tempfile.TemporaryDirectory() as root:
            text = "[web](https://example.com/x) [mail](mailto:a@b.c) [here](#top)\n```\n[no](nowhere.md)\n```\n`[no](nowhere.md)`\n"
            write(root, "README.md", text)
            self.assertEqual(check_docs.link_problems(root), [])

    def test_a_link_from_the_repository_root_and_a_parent_folder_resolve(self):
        with tempfile.TemporaryDirectory() as root:
            write(root, "AGENTS.md", "x\n")
            write(root, "docs/sub/a.md", "[up](../../AGENTS.md) [abs](/AGENTS.md)\n")
            self.assertEqual(check_docs.link_problems(root), [])


class DecisionTests(unittest.TestCase):
    def test_a_number_used_twice_and_a_record_missing_from_the_index_are_reported(self):
        with tempfile.TemporaryDirectory() as root:
            write(root, "docs/decisions/0001-a.md", "# a\n")
            write(root, "docs/decisions/0002-b.md", "# b\n")
            write(root, "docs/decisions/0002-c.md", "# c\n")
            write(root, "docs/decisions/README.md", "| [0001](0001-a.md) | a |\n| [0002](0002-b.md) | b |\n")
            problems = check_docs.decision_problems(root)
            self.assertTrue(any("0002" in p and "twice" in p for p in problems))
            self.assertTrue(any("0002-c.md" in p and "index" in p for p in problems))

    def test_a_consistent_set_has_no_problem(self):
        with tempfile.TemporaryDirectory() as root:
            write(root, "docs/decisions/0001-a.md", "# a\n")
            write(root, "docs/decisions/README.md", "| [0001](0001-a.md) | a |\n")
            self.assertEqual(check_docs.decision_problems(root), [])

    def test_a_replaced_record_whose_status_does_not_name_the_new_one_is_reported(self):
        with tempfile.TemporaryDirectory() as root:
            write(root, "docs/decisions/0001-a.md", "# a\n\n- Status: valid\n")
            write(root, "docs/decisions/0002-b.md", "# b\n\n- Status: valid in part (replaced by 0003)\n")
            write(root, "docs/decisions/0003-c.md", "# c\n\n- Status: valid\n- Replaces: [0001](0001-a.md) point 2\n- Replaces in part: [0002](0002-b.md)\n")
            write(root, "docs/decisions/README.md", "[0001](0001-a.md) [0002](0002-b.md) [0003](0003-c.md)\n")
            problems = check_docs.decision_problems(root)
            self.assertEqual(len(problems), 1)
            self.assertIn("0001-a.md", problems[0])
            self.assertIn("0003", problems[0])

    def test_a_refinement_does_not_need_a_status_change(self):
        with tempfile.TemporaryDirectory() as root:
            write(root, "docs/decisions/0001-a.md", "# a\n\n- Status: valid\n")
            write(root, "docs/decisions/0002-b.md", "# b\n\n- Status: valid\n- Refines: [0001](0001-a.md)\n")
            write(root, "docs/decisions/README.md", "[0001](0001-a.md) [0002](0002-b.md)\n")
            self.assertEqual(check_docs.decision_problems(root), [])


SPEC_TABLE = ("| ID | Scenario | Passes when | Where it is checked |\n|---|---|---|---|\n"
              "| PRD-01 | a | b | unit tests, real Mac |\n"
              "| PRD-02 | a | b | real Mac |\n"
              "| PRD-03 | (unused) | removed | — |\n"
              "| PRD-04 | a | b | UI tests |\n")


class ScenarioTagTests(unittest.TestCase):
    def test_a_scenario_checked_by_tests_needs_a_tagged_test(self):
        with tempfile.TemporaryDirectory() as root:
            write(root, "docs/specification.md", SPEC_TABLE)
            write(root, "Tests/A/ATests.swift", "// Checks PRD-01 (specification 7).\nstruct ATests {}\n")
            problems = check_docs.scenario_tag_problems(root)
            self.assertEqual(len(problems), 1)
            self.assertIn("PRD-04", problems[0])

    def test_a_tag_must_name_a_scenario_in_use(self):
        with tempfile.TemporaryDirectory() as root:
            write(root, "docs/specification.md", SPEC_TABLE)
            write(root, "Tests/A/ATests.swift", "// Checks PRD-01, PRD-04 (specification 7).\n// Checks PRD-03 and PRD-09.\n")
            problems = check_docs.scenario_tag_problems(root)
            joined = "\n".join(problems)
            self.assertIn("PRD-03", joined)
            self.assertIn("PRD-09", joined)
            self.assertNotIn("PRD-01", joined)
            self.assertEqual(len(problems), 2)

    def test_no_specification_means_nothing_to_check(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertEqual(check_docs.scenario_tag_problems(root), [])


def issue(number, *labels):
    return {"number": number, "labels": [{"name": name} for name in labels]}


class ReleaseCoverageTests(unittest.TestCase):
    def test_a_release_feature_needs_a_mark_in_the_specification_unless_it_says_no_spec(self):
        with tempfile.TemporaryDirectory() as root:
            write(root, "docs/specification.md", "rule `[not built #10]` and `[未実装 #11（×）、#12]`\n")
            release = [issue(10, "enhancement"), issue(13, "enhancement", "area:reader-view"), issue(14, "enhancement", "no-spec"),
                    issue(15, "bug"), issue(11, "enhancement"), issue(12, "enhancement")]
            problems = check_docs.release_spec_problems(root, release)
            self.assertEqual(len(problems), 1)
            self.assertIn("#13", problems[0])
            self.assertIn("no-spec", problems[0])

    def test_the_issues_a_pull_request_closes_need_no_mark(self):
        with tempfile.TemporaryDirectory() as root:
            write(root, "docs/specification.md", "nothing marked\n")
            release = [issue(10, "enhancement"), issue(11, "enhancement")]
            spec = check_docs.release_spec_problems(root, release, closing={10})
            self.assertEqual(len(spec), 1)
            self.assertIn("#11", spec[0])

    def test_the_closing_issues_are_read_from_a_list(self):
        self.assertEqual(check_docs.closing_issues("126, 139"), {126, 139})
        self.assertEqual(check_docs.closing_issues(""), set())

    def test_without_the_files_there_is_nothing_to_check(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertEqual(check_docs.release_spec_problems(root, [issue(1, "enhancement")]), [])

    def test_the_message_names_the_milestone(self):
        with tempfile.TemporaryDirectory() as root:
            write(root, "docs/specification.md", "nothing marked\n")
            unmarked = dict(issue(20, "enhancement"), milestone={"number": 3, "title": "1.1.0"})
            problems = check_docs.release_spec_problems(root, [unmarked])
            self.assertEqual(len(problems), 1)
            self.assertIn("milestone 1.1.0", problems[0])

    @staticmethod
    def fake_gh(answers, calls):
        """A stand-in for subprocess.run that answers `gh` calls from a dictionary keyed by the call's arguments."""
        class Result:
            def __init__(self, returncode, stdout, stderr=""):
                self.returncode, self.stdout, self.stderr = returncode, stdout, stderr
        def run(command, **_):
            calls.append(command)
            key = " ".join(command[1:3]) if command[1] == "api" else "issues " + command[command.index("--milestone") + 1]
            answer = answers.get(key)
            return Result(1, "", "not found") if answer is None else Result(0, json.dumps(answer))
        return run

    def test_every_open_milestone_is_read(self):
        calls = []
        answers = {
            "api repos/o/r/milestones?state=open&per_page=100": [{"number": 2, "title": "1.0.1"}, {"number": 3, "title": "1.1.0"}],
            "issues 2": [dict(issue(30, "bug"), milestone={"number": 2, "title": "1.0.1"})],
            "issues 3": [dict(issue(31, "enhancement"), milestone={"number": 3, "title": "1.1.0"})],
        }
        found = check_docs.github_release_issues("o/r", run=self.fake_gh(answers, calls))
        self.assertEqual(sorted(i["number"] for i in found), [30, 31])
        self.assertEqual(len(calls), 3)

    def test_no_open_milestone_means_no_release_issues(self):
        answers = {"api repos/o/r/milestones?state=open&per_page=100": []}
        self.assertEqual(check_docs.github_release_issues("o/r", run=self.fake_gh(answers, [])), [])

    def test_a_failed_gh_call_is_an_error_not_an_empty_list(self):
        answers = {"api repos/o/r/milestones?state=open&per_page=100": [{"number": 2, "title": "1.0.1"}]}
        with self.assertRaises(LookupError):
            check_docs.github_release_issues("o/r", run=self.fake_gh(answers, []))


class IssueReferenceTests(unittest.TestCase):
    def test_the_issues_named_in_status_marks_are_found(self):
        text = "a `[未実装 #139（×）、#140（Esc）]` b `[実装済み。いまは「一覧」。#139]` c `[not built #7]` d `[built]` e [link](#3) f `[not measured #8]`\n"
        found = check_docs.status_mark_issues(text)
        self.assertEqual(sorted(n for n, _ in found), [7, 8, 139, 139, 140])

    def test_roadmap_issues_count_except_in_the_history(self):
        base = "https://github.com/o/r/issues/"
        text = (f"## Now\n[#1]({base}1) and [#2]({base}2)\n## Done (history)\n[#3]({base}3)\n## Candidates\n[#4]({base}4)\n")
        self.assertEqual(sorted(n for n, _ in check_docs.roadmap_issues(text)), [1, 2, 4])

    def test_a_closed_issue_in_a_mark_or_the_active_roadmap_is_reported_and_an_open_one_is_not(self):
        with tempfile.TemporaryDirectory() as root:
            write(root, "docs/specification.md", "rule `[未実装 #10]` and `[not built #11]`\n")
            base = "https://github.com/o/r/issues/"
            write(root, "docs/roadmap.md", f"## Now\n[#12]({base}12)\n## Done (history)\n[#13]({base}13)\n")
            states = {10: "OPEN", 11: "CLOSED", 12: "CLOSED", 13: "CLOSED"}
            problems = check_docs.issue_problems(root, lambda n: states[n])
            joined = "\n".join(problems)
            self.assertIn("#11", joined)
            self.assertIn("#12", joined)
            self.assertNotIn("#10", joined)
            self.assertNotIn("#13", joined)

    def test_an_issue_that_cannot_be_found_is_reported(self):
        with tempfile.TemporaryDirectory() as root:
            write(root, "docs/specification.md", "`[未実装 #99]`\n")

            def lookup(number):
                raise LookupError("no such issue")

            problems = check_docs.issue_problems(root, lookup)
            self.assertTrue(any("#99" in p for p in problems))


if __name__ == "__main__":
    unittest.main(verbosity=2)
