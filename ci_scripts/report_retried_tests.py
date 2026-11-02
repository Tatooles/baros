#!/usr/bin/env python3
"""Flag tests that failed and then passed on retry, so a green run doesn't hide flakes."""

import json
import os
import subprocess
import sys


def retried_tests(node):
    if node.get("nodeType") == "Test Case":
        attempts = [
            child for child in node.get("children", [])
            if child.get("nodeType") == "Repetition"
        ]
        failed = any(attempt.get("result") == "Failed" for attempt in attempts)
        if failed and node.get("result") == "Passed":
            yield node.get("nodeIdentifier") or node.get("name", "Unknown test")
        return

    for child in node.get("children", []):
        yield from retried_tests(child)


def main():
    results = json.loads(
        subprocess.check_output(
            ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", sys.argv[1], "--compact"]
        )
    )
    tests = [test for node in results.get("testNodes", []) for test in retried_tests(node)]

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    for test in tests:
        print(f"::warning title=Flaky test passed on retry::{test}")
        if summary_path:
            with open(summary_path, "a", encoding="utf-8") as summary:
                summary.write(f"- Passed on retry: `{test}`\n")

    print(f"{len(tests)} test(s) passed only on retry.")


if __name__ == "__main__":
    main()
