#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
mkdir -p "$REPO_ROOT/build"
TEST_DIRECTORY="$(mktemp -d "$REPO_ROOT/build/gateway-admin-helper-test.XXXXXX")"
trap 'rm -rf "$TEST_DIRECTORY"' EXIT

xcrun swiftc -parse-as-library -swift-version 5 -D GATEWAY_ADMIN_HELPER_TESTING \
    "$REPO_ROOT/DefenseClawMac/DataLayer/GatewayAdminProtocol.swift" \
    "$REPO_ROOT/GatewayAdminHelper/main.swift" \
    "$REPO_ROOT/Tests/GatewayAdminHelperTests.swift" \
    -o "$TEST_DIRECTORY/gateway-admin-helper-tests" \
    -framework Foundation -framework Security
"$TEST_DIRECTORY/gateway-admin-helper-tests" "$TEST_DIRECTORY"
