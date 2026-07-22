#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-runtime-contract-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
MODULE_CACHE="$BUILD_DIR/ModuleCache"
mkdir -p "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" xcrun swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT/DefenseClawMac/DataLayer/CommandRegistry.swift" \
  "$ROOT/Tests/RuntimeContractSurfaceTests.swift" \
  -o "$BUILD_DIR/RuntimeContractSurfaceTests"

"$BUILD_DIR/RuntimeContractSurfaceTests"

if grep -Fq 'key: "otel.' "$ROOT/DefenseClawMac/Features/ConfigEditorDefinitions.swift"; then
  echo "Legacy config-v7 otel.* editor fields remain" >&2
  exit 1
fi

if grep -Fq 'migrate-splunk' "$ROOT/DefenseClawMac/DataLayer/CommandRegistry.swift"; then
  echo "Retired migrate-splunk command remains" >&2
  exit 1
fi

if grep -Fq 'Search 226 commands' "$ROOT/DefenseClawMac/Features/CommandPaletteView.swift"; then
  echo "Command palette still contains a stale hard-coded count" >&2
  exit 1
fi
