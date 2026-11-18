#!/usr/bin/env python3
"""Print the identifiers of tests that still failed after any retries, one per line.

Usage: report_failed_tests.py <xcresult> [<xcodebuild log>]

The result bundle is authoritative. When it can't be read, for example because the
test step hit its timeout before xcodebuild finalized it, the xcodebuild log is used
instead. The log fallback also reports tests that never recorded a result: ones that
exceeded their execution time allowance, crashed the test runner, or were still
running when the log ended. XCTest doesn't retry those, and doesn't print "failed".
"""

import json
import os
import re
import subprocess
import sys

TEST_CASE = re.compile(r"Test Case '-\[(?:\w+\.)?(\w+) (\w+)\]' (started|passed|failed|skipped|exceeded)")
RUNNER_RESTART = "Restarting after unexpected exit, crash, or test timeout"
NOTES = {
    "failed": "",
    "exceeded": " (exceeded its execution time allowance)",
    "restarted": " (crashed or was killed before recording a result)",
    "started": " (no result recorded)",
    "running": " (still running when the log ended)",
}


def failed_tests(node):
    if node.get("nodeType") == "Test Case":
        if node.get("result") == "Failed":
            yield node.get("nodeIdentifier") or node.get("name", "Unknown test")
        return

    for child in node.get("children", []):
        yield from failed_tests(child)


def failed_tests_from_result_bundle(path):
    results = json.loads(
        subprocess.check_output(
            ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", path, "--compact"]
        )
    )
    return [test for node in results.get("testNodes", []) for test in failed_tests(node)]


def failed_tests_from_log(path):
    # The last outcome for each test wins, so a test that passed on retry is not reported.
    outcomes = {}
    current = None
    with open(path, encoding="utf-8", errors="replace") as log:
        for line in log:
            if RUNNER_RESTART in line:
                if current and outcomes[current] == "started":
                    outcomes[current] = "restarted"
                current = None
                continue
            match = TEST_CASE.search(line)
            if not match:
                continue
            test_class, test_name, outcome = match.groups()
            identifier = f"{test_class}/{test_name}()"
            outcomes[identifier] = outcome
            current = identifier if outcome in ("started", "exceeded") else None

    if current and outcomes[current] == "started":
        outcomes[current] = "running"
    return [f"{test}{NOTES[outcome]}" for test, outcome in outcomes.items() if outcome in NOTES]


def main():
    source = "result bundle"
    try:
        tests = failed_tests_from_result_bundle(sys.argv[1])
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        if len(sys.argv) < 3 or not os.path.exists(sys.argv[2]):
            print("Neither the result bundle nor the xcodebuild log could be read.", file=sys.stderr)
            sys.exit(1)
        print("Result bundle unreadable; reading failed tests from the log.", file=sys.stderr)
        tests = failed_tests_from_log(sys.argv[2])
        source = "log"

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path and tests:
        with open(summary_path, "a", encoding="utf-8") as summary:
            summary.writelines(f"- Failed ({source}): `{test}`\n" for test in tests)

    for test in tests:
        print(test)


if __name__ == "__main__":
    main()
