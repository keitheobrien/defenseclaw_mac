#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-policy-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUILD_DIR/cache" "$ROOT/DefenseClawMac/DataLayer/PolicyCatalog.swift" "$ROOT/Tests/PolicyCatalogModelTests.swift" -o "$BUILD_DIR/test"
"$BUILD_DIR/test"
