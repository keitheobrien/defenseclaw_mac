#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d /private/tmp/defenseclaw-canonical-tests.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$ROOT/DefenseClawMac/DataLayer/Models.swift" \
  "$ROOT/DefenseClawMac/DataLayer/AuditStore.swift" \
  "$ROOT/DefenseClawMac/DataLayer/EventStreamReader.swift" \
  "$ROOT/Tests/CanonicalEventHistoryTests.swift" \
  -lsqlite3 -o "$BUILD_DIR/CanonicalEventHistoryTests"
"$BUILD_DIR/CanonicalEventHistoryTests" "$@"
