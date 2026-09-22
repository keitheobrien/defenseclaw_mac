#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-gateway-auto-start-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc -parse-as-library \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$ROOT/DefenseClawMac/DataLayer/GatewayAutoStartCoordinator.swift" \
  "$ROOT/Tests/GatewayAutoStartTests.swift" \
  -o "$BUILD_DIR/GatewayAutoStartTests"
"$BUILD_DIR/GatewayAutoStartTests"
