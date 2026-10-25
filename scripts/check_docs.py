#!/usr/bin/env python3
"""Keeps the documents honest. Run it from the repository root (CI runs it on every pull request).

  python3 scripts/check_docs.py             Offline: relative links resolve, decision numbers are unique and in the index,
                                            a record that a newer one replaces names the newer one in its Status, and each
                                            acceptance scenario checked by tests is named by a test (`// Checks PRD-04`).
  python3 scripts/check_docs.py --online    Also: the issues named in the specification's status marks and in the active
                                            parts of the roadmap are open (a closed issue means the mark or the line is
                                            stale); and every open `enhancement` of an open milestone (one per release,
                                            decision 0071) is named by a status mark of the specification, or has the label
                                            `no-spec`. Needs `gh` and a token (GH_TOKEN) that can read issues.

The problems are printed as `path:line: message`; the exit status is 1 when there is any.
"""
import argparse
import json
import os
import re
import subprocess
import sys

SKIP_DIRS = {".git", ".build", ".claude", ".superpowers", "node_modules"}
MARK = re.compile(r"\[(\s*(?:未実装|実装済み|not built|not measured|built)[^\]]*)\]")
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
ISSUE_NUMBER = re.compile(r"#(\d+)")
ROADMAP_ISSUE = re.compile(r"issues/(\d+)\b")


def markdown_files(root):
    """README.md, AGENTS.md, and every Markdown file under docs/ and .github/."""
    found = []
    for name in ("README.md", "AGENTS.md"):
        if os.path.isfile(os.path.join(root, name)):
            found.append(name)
    for top in ("docs", ".github"):
        for folder, dirs, files in os.walk(os.path.join(root, top)):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for file in files:
                if file.endswith(".md"):
                    found.append(os.path.relpath(os.path.join(folder, file), root))
    return sorted(found)


def read_lines(root, relative):
    with open(os.path.join(root, relative), encoding="utf-8") as handle:
        return handle.read().split("\n")


def link_problems(root):
    problems = []
    for relative in markdown_files(root):
        in_fence = False
        for number, line in enumerate(read_lines(root, relative), 1):
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for target in LINK.findall(re.sub(r"`[^`]*`", "", line)):
                if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target) or target.startswith("#") or target.startswith("<"):
                    continue
                path = re.split(r"[#?]", target, maxsplit=1)[0]
                if not path:
                    continue
                base = root if path.startswith("/") else os.path.dirname(os.path.join(root, relative))
                resolved = os.path.normpath(os.path.join(base, path.lstrip("/")) if path.startswith("/") else os.path.join(base, path))
                if not os.path.exists(resolved):
                    problems.append(f"{relative}:{number}: the link '{target}' points to a file that does not exist")
    return problems


def decision_problems(root):
    folder = os.path.join(root, "docs", "decisions")
    if not os.path.isdir(folder):
        return []
    problems = []
    seen = {}
    for name in sorted(os.listdir(folder)):
        match = re.match(r"^(\d{4})-.*\.md$", name)
        if not match:
            continue
        seen.setdefault(match.group(1), []).append(name)
    index_path = os.path.join(folder, "README.md")
    index = open(index_path, encoding="utf-8").read() if os.path.isfile(index_path) else ""
    for number, names in sorted(seen.items()):
        if len(names) > 1:
            problems.append(f"docs/decisions: the number {number} is used twice ({', '.join(names)}): renumber the newer one")
        for name in names:
            if f"]({name})" not in index:
                problems.append(f"docs/decisions/{name}: not in the index (docs/decisions/README.md)")
    problems += replaced_status_problems(folder, seen)
    return problems


def header_field(lines, field):
    """The value of a header line such as `- Status: valid` (only the lines before the first section)."""
    for line in lines:
        if line.startswith("## "):
            break
        if line.startswith(f"- {field}:"):
            return line[len(field) + 3:].strip()
    return None


def replaced_status_problems(folder, seen):
    """A record named on a newer record's `- Replaces:` (or `- Replaces in part:`) line must name the newer one in its Status."""
    problems = []
    texts = {number: open(os.path.join(folder, names[0]), encoding="utf-8").read().split("\n") for number, names in seen.items()}
    for number, lines in sorted(texts.items()):
        for field in ("Replaces", "Replaces in part"):
            value = header_field(lines, field) or ""
            for old in re.findall(r"\]\((\d{4})-[^)]*\.md\)", value):
                if old not in texts or old == number:
                    continue
                status = header_field(texts[old], "Status") or header_field(texts[old], "状態") or ""
                if number not in status:
                    problems.append(f"docs/decisions/{seen[old][0]}: replaced by {number}, but its Status does not say so")
    return problems


SCENARIO = re.compile(r"\bPRD-\d{2}\b")


def scenario_tag_problems(root):
    """Each acceptance scenario (specification 7) checked by "unit tests" or "UI tests" has a test that names it
    (`// Checks PRD-04`), and every name in Tests/ is a scenario in use."""
    path = os.path.join(root, "docs", "specification.md")
    if not os.path.isfile(path):
        return []
    tested, in_use = set(), set()
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if len(cells) < 4 or not re.fullmatch(r"PRD-\d{2}", cells[0]):
                continue
            if cells[1].startswith("(unused)"):
                continue
            in_use.add(cells[0])
            if re.search(r"\b(unit|UI) tests\b", cells[-1]):
                tested.add(cells[0])
    named = {}
    for folder, dirs, files in os.walk(os.path.join(root, "Tests")):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for file in sorted(files):
            if not file.endswith(".swift"):
                continue
            relative = os.path.relpath(os.path.join(folder, file), root)
            with open(os.path.join(folder, file), encoding="utf-8") as handle:
                for number, line in enumerate(handle, 1):
                    for scenario in SCENARIO.findall(line):
                        named.setdefault(scenario, f"{relative}:{number}")
    problems = [f"docs/specification.md: {scenario} is checked by tests, but no test names it (add `// Checks {scenario}` to the suite)"
                for scenario in sorted(tested - set(named))]
    problems += [f"{where}: {scenario} is not a scenario in use in specification 7"
                 for scenario, where in sorted(named.items()) if scenario not in in_use]
    return problems


def status_mark_issues(text):
    """(issue number, line) for every issue named inside a status mark such as `[未実装 #139]` or `[not built #7]`."""
    found = []
    for number, line in enumerate(text.split("\n"), 1):
        for mark in MARK.findall(line):
            for issue in ISSUE_NUMBER.findall(mark):
                found.append((int(issue), number))
    return found


def roadmap_issues(text):
    """(issue number, line) for the issues linked outside the section 'Done (history)'."""
    found = []
    skipping = False
    for number, line in enumerate(text.split("\n"), 1):
        if line.startswith("## "):
            skipping = line.startswith("## Done")
        if skipping:
            continue
        for issue in ROADMAP_ISSUE.findall(line):
            found.append((int(issue), number))
    return found


def issue_problems(root, state_of):
    """`state_of(number)` returns 'OPEN' or 'CLOSED' (it may raise when the issue does not exist)."""
    problems = []
    cache = {}

    def state(number):
        if number not in cache:
            try:
                cache[number] = state_of(number)
            except Exception as error:  # noqa: BLE001 - any failure is reported as a problem of the reference
                cache[number] = f"UNKNOWN: {error}"
        return cache[number]

    checks = [("docs/specification.md", status_mark_issues, "the status mark names #{n}, which is closed: remove the mark (the work is done)"),
              ("docs/roadmap.md", roadmap_issues, "#{n} is closed: move the line to 'Done (history)' or remove it")]
    for relative, finder, message in checks:
        path = os.path.join(root, relative)
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        for number, line in finder(text):
            current = state(number)
            if current == "CLOSED":
                problems.append(f"{relative}:{line}: " + message.format(n=number))
            elif current != "OPEN":
                problems.append(f"{relative}:{line}: #{number} cannot be read ({current}): fix the number")
    return problems


def label_names(issue):
    return {label["name"] for label in issue.get("labels", [])}


def closing_issues(text):
    """The issue numbers in a list such as "126, 139" (the issues a pull request closes)."""
    return {int(n) for n in re.findall(r"\d+", text or "")}


def release_spec_problems(root, release_issues, closing=frozenset()):
    """Every open `enhancement` issue of an open release milestone is named by a status mark of the specification
    (`[not built #n]`), unless it has the label `no-spec` (it changes nothing the person sees). An issue the pull request
    closes is done: its mark goes away in that pull request."""
    path = os.path.join(root, "docs", "specification.md")
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8") as handle:
        marked = {number for number, _ in status_mark_issues(handle.read())}
    return [f"docs/specification.md: #{issue['number']} is an enhancement of the milestone {milestone_title(issue)}, but no status mark "
            f"names it: write the behavior in the specification with `[not built #{issue['number']}]`, or give the issue the label `no-spec`"
            for issue in release_issues
            if "enhancement" in label_names(issue) and "no-spec" not in label_names(issue)
            and issue["number"] not in marked and issue["number"] not in closing]


def milestone_title(issue):
    return (issue.get("milestone") or {}).get("title") or "?"


def github_release_issues(repository, run=subprocess.run):
    """The open issues of every open milestone: each release has one, named by its version (decision 0071)."""
    def gh(arguments):
        result = run(["gh", *arguments], capture_output=True, text=True, check=False)
        if result.returncode != 0:
            raise LookupError(result.stderr.strip() or "gh failed")
        return json.loads(result.stdout)
    issues = []
    for milestone in gh(["api", f"repos/{repository}/milestones?state=open&per_page=100"]):
        issues += gh(["issue", "list", "--repo", repository, "--milestone", str(milestone["number"]), "--state", "open",
                      "--limit", "200", "--json", "number,labels,milestone"])
    return issues


def github_state(repository):
    def lookup(number):
        result = subprocess.run(["gh", "api", f"repos/{repository}/issues/{number}", "--jq", ".state"],
                                capture_output=True, text=True, check=False)
        if result.returncode != 0:
            raise LookupError(result.stderr.strip() or "gh failed")
        return result.stdout.strip().upper()
    return lookup


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    parser.add_argument("--online", action="store_true", help="also check the issues named in the marks and the roadmap")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--closing", default=os.environ.get("CLOSING_ISSUES", ""),
                        help="the issues the pull request closes, such as \"126,139\": the release check treats them as done")
    args = parser.parse_args(argv)
    problems = link_problems(args.root) + decision_problems(args.root) + scenario_tag_problems(args.root)
    if args.online:
        repository = args.repo
        if not repository:
            result = subprocess.run(["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
                                    capture_output=True, text=True, check=False)
            repository = result.stdout.strip()
        if not repository:
            problems.append("--online needs the repository: set GITHUB_REPOSITORY or --repo owner/name")
        else:
            problems += issue_problems(args.root, github_state(repository))
            try:
                release = github_release_issues(repository)
            except (LookupError, ValueError) as error:
                problems.append(f"the issues of the open milestones cannot be read ({error})")
            else:
                closing = closing_issues(args.closing)
                problems += release_spec_problems(args.root, release, closing)
    if problems:
        print("\n".join(problems))
        print(f"\ndocs check: {len(problems)} problem(s)")
        return 1
    print("docs check: OK" + (" (links, decisions, scenarios, issues)" if args.online else " (links, decisions, scenarios; run with --online for the issues)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
