#!/usr/bin/env python3
"""Print the identifiers of tests that still failed after any retries, one per line."""

import json
import os
import subprocess
import sys


def failed_tests(node):
    if node.get("nodeType") == "Test Case":
        if node.get("result") == "Failed":
            yield node.get("nodeIdentifier") or node.get("name", "Unknown test")
        return

    for child in node.get("children", []):
        yield from failed_tests(child)


def main():
    results = json.loads(
        subprocess.check_output(
            ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", sys.argv[1], "--compact"]
        )
    )
    tests = [test for node in results.get("testNodes", []) for test in failed_tests(node)]

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path and tests:
        with open(summary_path, "a", encoding="utf-8") as summary:
            summary.writelines(f"- Failed: `{test}`\n" for test in tests)

    for test in tests:
        print(test)


if __name__ == "__main__":
    main()
