#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-gateway-admin-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$ROOT/DefenseClawMac/DataLayer/InstallationContext.swift" \
  "$ROOT/DefenseClawMac/DataLayer/ConfigStore.swift" \
  "$ROOT/DefenseClawMac/DataLayer/CLIRunner.swift" \
  "$ROOT/DefenseClawMac/DataLayer/GatewayAdminProtocol.swift" \
  "$ROOT/DefenseClawMac/DataLayer/GatewayAdministratorClient.swift" \
  "$ROOT/Tests/GatewayAdministratorTests.swift" \
  -o "$BUILD_DIR/GatewayAdministratorTests"
"$BUILD_DIR/GatewayAdministratorTests"
# Compile the real helper and verify that direct unprivileged execution refuses
# before opening a listener or mutating any state.
xcrun swiftc -parse-as-library \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$ROOT/DefenseClawMac/DataLayer/GatewayAdminProtocol.swift" \
  "$ROOT/GatewayAdminHelper/main.swift" \
  -o "$BUILD_DIR/DefenseClawGatewayHelper"
set +e
"$BUILD_DIR/DefenseClawGatewayHelper" > "$BUILD_DIR/helper-output" 2>&1
status=$?
set -e
if [[ "$status" != 77 ]]; then
  cat "$BUILD_DIR/helper-output"
  echo "Expected direct helper execution to refuse with status 77" >&2
  exit 1
fi
