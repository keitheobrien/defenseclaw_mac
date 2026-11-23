#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/defenseclaw-upgrade-agent-tests.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
xcrun swiftc \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$ROOT/DefenseClawMac/DataLayer/InstallationContext.swift" \
  "$ROOT/DefenseClawMac/DataLayer/ConfigStore.swift" \
  "$ROOT/DefenseClawMac/DataLayer/CLIRunner.swift" \
  "$ROOT/DefenseClawMac/DataLayer/RuntimeUpgradeAgents.swift" \
  "$ROOT/DefenseClawMac/DataLayer/GatewayAdminProtocol.swift" \
  "$ROOT/DefenseClawMac/DataLayer/GatewayAdministratorClient.swift" \
  "$ROOT/Tests/RuntimeUpgradeAgentsTests.swift" \
  -o "$BUILD_DIR/RuntimeUpgradeAgentsTests"
"$BUILD_DIR/RuntimeUpgradeAgentsTests"
