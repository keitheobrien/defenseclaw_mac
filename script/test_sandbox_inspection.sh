#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-inspection-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
MODULE_CACHE="$BUILD_DIR/ModuleCache"
mkdir -p "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" xcrun swiftc \
  -module-cache-path "$MODULE_CACHE" \
  "$ROOT/DefenseClawMac/DataLayer/InstallationContext.swift" \
  "$ROOT/DefenseClawMac/DataLayer/ConfigStore.swift" \
  "$ROOT/DefenseClawMac/DataLayer/CLIRunner.swift" \
  "$ROOT/DefenseClawMac/DataLayer/GatewayAdminProtocol.swift" \
  "$ROOT/DefenseClawMac/DataLayer/GatewayAdministratorClient.swift" \
  "$ROOT/DefenseClawMac/DataLayer/Models.swift" \
  "$ROOT/DefenseClawMac/DataLayer/SandboxModels.swift" \
  "$ROOT/DefenseClawMac/DataLayer/SandboxInspection.swift" \
  "$ROOT/DefenseClawMac/DataLayer/SandboxInspectionStore.swift" \
  "$ROOT/Tests/SandboxInspectionTests.swift" \
  -o "$BUILD_DIR/SandboxInspectionTests"

"$BUILD_DIR/SandboxInspectionTests"
