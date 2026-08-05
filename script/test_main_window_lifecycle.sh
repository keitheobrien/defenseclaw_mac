#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-main-window-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
MODULE_CACHE="$BUILD_DIR/ModuleCache"
mkdir -p "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" xcrun swiftc \
  -parse-as-library \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT/Tests/MainWindowLifecycleContractTests.swift" \
  -o "$BUILD_DIR/MainWindowLifecycleContractTests"

"$BUILD_DIR/MainWindowLifecycleContractTests" "$ROOT"
