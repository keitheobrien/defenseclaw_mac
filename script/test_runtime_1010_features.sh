#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-runtime1010-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$ROOT/DefenseClawMac/DataLayer/CommandRegistry.swift" \
  "$ROOT/DefenseClawMac/DataLayer/Runtime1010Features.swift" \
  "$ROOT/Tests/Runtime1010FeatureTests.swift" -o "$BUILD_DIR/tests"
"$BUILD_DIR/tests" "${RUNTIME_1010_TEST_PLAN:-$BUILD_DIR/plan.json}"
