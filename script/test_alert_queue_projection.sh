#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-alert-queue-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
MODULE_CACHE="$BUILD_DIR/ModuleCache"
mkdir -p "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" xcrun swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT/DefenseClawMac/DataLayer/Models.swift" \
  "$ROOT/DefenseClawMac/DataLayer/AuditStore.swift" \
  "$ROOT/Tests/AlertQueueProjectionTests.swift" \
  -lsqlite3 \
  -o "$BUILD_DIR/AlertQueueProjectionTests"

"$BUILD_DIR/AlertQueueProjectionTests"
