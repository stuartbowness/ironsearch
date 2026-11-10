#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Compile only the Foundation-based core against the host SDK. This lets CI
# check ranking and argument handling without the app's macOS 27 requirement.
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ironsearch-checks.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -emit-library -emit-module -module-name SearchCore \
    Sources/SearchCore/*.swift -emit-module-path "$CHECK_DIR/SearchCore.swiftmodule" \
    -o "$CHECK_DIR/libSearchCore.dylib"
swiftc -parse-as-library -I "$CHECK_DIR" -L "$CHECK_DIR" -lSearchCore \
    -Xlinker -rpath -Xlinker "$CHECK_DIR" \
    Tests/SearchCoreTests/SearchEngineTests.swift -o "$CHECK_DIR/SearchChecks"
"$CHECK_DIR/SearchChecks"
