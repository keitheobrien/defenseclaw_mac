#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-redaction-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUILD_DIR/cache" "$ROOT/DefenseClawMac/DataLayer/RedactionCommands.swift" "$ROOT/Tests/RedactionCommandTests.swift" -o "$BUILD_DIR/test"
"$BUILD_DIR/test"
