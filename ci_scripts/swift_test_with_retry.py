#!/usr/bin/env python3
"""Run `swift test` for a package, retrying failed tests once like the hosted iOS gates.

A test that fails and then passes on retry is reported as a flaky warning, so a
green run doesn't hide it. A build failure, a crash, or a test that fails twice
fails the step.

Usage: swift_test_with_retry.py <package-path> <log-path>
"""

import os
import re
import subprocess
import sys

FAILED_CASE = re.compile(r"Test Case '-\[(\S+)\.(\S+) (\S+)\]' failed")
ANY_FAILED_CASE = re.compile(r"^Test Case '.*' failed", re.MULTILINE)
CASE_FAILURE = re.compile(r"error: -\[\S+ \S+\] : ")
ALL_TESTS_SUMMARY = re.compile(
    r"^Test Suite 'All tests' (?:passed|failed) at .*\n\s*Executed \d+ tests?, with (\d+) failures?",
    re.MULTILINE,
)
SWIFT_TESTING_FAILED = re.compile(r"Test run with \d+ tests?\b.* failed")


def run(args, log):
    print("+ " + " ".join(args), flush=True)
    log.write("+ " + " ".join(args) + "\n")
    process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    output = []
    for line in process.stdout:
        sys.stdout.write(line)
        log.write(line)
        output.append(line)
    return process.wait(), "".join(output)


def main():
    package_path, log_path = sys.argv[1], sys.argv[2]
    base = ["swift", "test", "--package-path", package_path]

    with open(log_path, "w", encoding="utf-8") as log:
        status, output = run(base, log)
        if status == 0:
            print("0 test(s) passed only on retry.")
            return 0

        failed = sorted({f"{module}.{cls}/{test}" for module, cls, test in FAILED_CASE.findall(output)})
        # Retry only when the whole XCTest run finished and every failure it
        # counted belongs to a parsed test case. A build failure, a crash, a
        # suite-level failure, or a Swift Testing failure fails the step,
        # because a filtered retry can't cover them.
        summary = ALL_TESTS_SUMMARY.search(output)
        accounted = (
            summary is not None
            and int(summary.group(1)) == len(CASE_FAILURE.findall(output))
            and len(ANY_FAILED_CASE.findall(output)) == len(FAILED_CASE.findall(output))
        )
        if not failed or not accounted or "unexpected signal" in output or SWIFT_TESTING_FAILED.search(output):
            print("swift test failed in a way a retry can't cover (build failure, crash, or unnamed failure).")
            return 1

        pattern = "|".join(f"^{re.escape(name)}$" for name in failed)
        print(f"Retrying {len(failed)} failed test(s) once.", flush=True)
        status, _ = run(base + ["--skip-build", "--filter", pattern], log)
        if status != 0:
            return 1

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    for name in failed:
        print(f"::warning title=Flaky test passed on retry::{name}")
        if summary_path:
            with open(summary_path, "a", encoding="utf-8") as summary:
                summary.write(f"- Passed on retry: `{name}`\n")
    print(f"{len(failed)} test(s) passed only on retry.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
