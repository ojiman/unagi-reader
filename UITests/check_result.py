"""Reject a missing, partial, skipped or failed UI smoke run."""
import json
import sys


def check(summary):
    if not (summary.get("result") == "Passed"
            and summary.get("totalTestCount") == 7
            and summary.get("passedTests") == 7
            and summary.get("failedTests") == 0
            and summary.get("skippedTests") == 0):
        raise ValueError("Expected all seven UI smoke tests to finish and pass: " + str(summary))


if __name__ == "__main__":
    with open(sys.argv[1]) as source:
        check(json.load(source))
    print("All seven UI smoke tests finished and passed.")
