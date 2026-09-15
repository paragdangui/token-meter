#!/bin/bash
# Runs the test suite. Extra arguments pass through, e.g. scripts/test.sh --filter UsageParsingTests
set -euo pipefail
cd "$(dirname "$0")/.."
flags=()
# CommandLineTools ships the Swift Testing macro plugin but SwiftPM doesn't find it without Xcode.
PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ "$(xcode-select -p)" == *CommandLineTools* && -d "$PLUGINS" ]]; then
    flags=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
fi
swift test ${flags[@]+"${flags[@]}"} "$@"
