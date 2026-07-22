#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-inspector-layout-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
MODULE_CACHE="$BUILD_DIR/ModuleCache"
mkdir -p "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" xcrun swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT/DefenseClawMac/DesignSystem/InspectorLayoutPolicy.swift" \
  "$ROOT/Tests/InspectorLayoutPolicyTests.swift" \
  -o "$BUILD_DIR/InspectorLayoutPolicyTests"

"$BUILD_DIR/InspectorLayoutPolicyTests"
