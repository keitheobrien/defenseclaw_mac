#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-detail-parser-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
MODULE_CACHE="$BUILD_DIR/ModuleCache"
mkdir -p "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" xcrun swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT/DefenseClawMac/DataLayer/StructuredDetailParser.swift" \
  "$ROOT/Tests/StructuredDetailParserTests.swift" \
  -o "$BUILD_DIR/StructuredDetailParserTests"

"$BUILD_DIR/StructuredDetailParserTests"
