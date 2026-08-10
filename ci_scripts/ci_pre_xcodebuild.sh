#!/bin/sh

set -eu

if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
  exit 0
fi

if command -v sentry-cli >/dev/null 2>&1; then
  exit 0
fi

brew install getsentry/tools/sentry-cli
