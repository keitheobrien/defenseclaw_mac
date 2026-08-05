#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-runtime-artifact-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
MODULE_CACHE="$BUILD_DIR/ModuleCache"
mkdir -p "$MODULE_CACHE"

# RuntimePayload is intentionally kept in RuntimeInstaller.swift beside its
# only consumer. Compile that production type without the AppState extension.
sed '/^enum RuntimeInstallState:/,$d' \
  "$ROOT/DefenseClawMac/DataLayer/RuntimeInstaller.swift" \
  > "$BUILD_DIR/RuntimePayload.swift"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" xcrun swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$BUILD_DIR/RuntimePayload.swift" \
  "$ROOT/Tests/RuntimeProtectedArtifactTests.swift" \
  -o "$BUILD_DIR/RuntimeProtectedArtifactTests"

"$BUILD_DIR/RuntimeProtectedArtifactTests"
